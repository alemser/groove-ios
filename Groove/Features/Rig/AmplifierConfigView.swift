import SwiftUI
import UniformTypeIdentifiers

/// Wraps a profile export/import JSON payload for `.fileExporter`/`.fileImporter`.
struct AmplifierProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Editable amplifier config: device attributes, the inputs table, and
/// profile management — mirrors the web studio's Amplifier tab.
struct AmplifierConfigView: View {
    let equipmentModel: EquipmentRemoteModel

    @Environment(AppSettings.self) private var settings
    @State private var model = AmplifierConfigModel()

    @State private var maker = ""
    @State private var deviceModel = ""
    @State private var inputMode = "cycle"
    @State private var warmUpSecs = ""
    @State private var standbyTimeoutMins = ""
    @State private var inputs: [RigInputConfig] = []

    @State private var selectedProfileId = ""
    @State private var showSaveProfileSheet = false
    @State private var newProfileName = ""
    @State private var exportDocument: AmplifierProfileDocument?
    @State private var showExporter = false
    @State private var showImporter = false

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading amplifier config…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .onChange(of: model.config) { _, new in seed(from: new) }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(model.isSaving)
            }
        }
        .sheet(isPresented: $showSaveProfileSheet) { saveProfileSheet }
        .alert(
            "Unsaved Changes",
            isPresented: Binding(
                get: { model.pendingForceActivate != nil },
                set: { if !$0 { model.pendingForceActivate = nil } }
            ),
            presenting: model.pendingForceActivate
        ) { pending in
            // The server auto-saves the diverged live config as its own
            // profile before switching (see AmplifierConfigModel.activate),
            // so this is never a true, unrecoverable discard.
            Button("Back Up and Activate", role: .destructive) {
                Task { await model.activate(profileId: pending.profileId, force: true) }
            }
            Button("Cancel", role: .cancel) { model.pendingForceActivate = nil }
        } message: { pending in
            Text(pending.message)
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "amplifier-profile") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            Task { await handleImport(result) }
        }
    }

    private var content: some View {
        Form {
            if let backupId = model.lastBackupProfileId {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ok)
                        Text("Your previous setup was saved as profile \"\(backupId)\".")
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                        Spacer()
                        Button("Dismiss") { model.lastBackupProfileId = nil }
                            .font(.footnote)
                    }
                }
            }

            profileSection

            commandsSection

            Section("Device") {
                TextField("Maker", text: $maker)
                TextField("Model", text: $deviceModel)
                Picker("Input Mode", selection: $inputMode) {
                    Text("Cycle").tag("cycle")
                    Text("Direct").tag("direct")
                }
                TextField("Warm-up (secs)", text: $warmUpSecs)
                    .keyboardType(.numberPad)
                TextField("Standby timeout (mins)", text: $standbyTimeoutMins)
                    .keyboardType(.numberPad)
            }

            Section {
                ForEach($inputs) { $input in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Label", text: $input.label)
                        Toggle("Visible", isOn: $input.visible)
                        Picker("Recognition", selection: Binding(
                            get: { input.recognitionPolicy ?? "auto" },
                            set: { input.recognitionPolicy = $0 }
                        )) {
                            Text("Auto").tag("auto")
                            Text("Library").tag("library")
                            Text("Display Only").tag("display_only")
                            Text("Off").tag("off")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { inputs.remove(atOffsets: $0) }

                Button {
                    inputs.append(RigInputConfig(id: "_new_\(UUID().uuidString)", label: "New Input", visible: true, recognitionPolicy: "auto"))
                } label: {
                    Label("Add Input", systemImage: "plus")
                }
            } header: {
                Text("Inputs")
            } footer: {
                Text("What each source is called and whether recognition runs on it.")
                    .foregroundStyle(Brand.muted)
            }

            if let error = model.actionError {
                Section { Text(error).foregroundStyle(Brand.err) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var commandsSection: some View {
        if let amp = equipmentModel.amplifierEquipment {
            Section {
                NavigationLink {
                    AmplifierCommandsView(item: amp, ampConfig: model.config, model: equipmentModel)
                } label: {
                    let learned = (amp.actions ?? []).filter { equipmentModel.isLearned(targetId: amp.id, action: $0) }.count
                    let total = (amp.actions ?? []).count
                    HStack {
                        Label("Remote Commands", systemImage: "wand.and.stars")
                            .foregroundStyle(Brand.text)
                        Spacer()
                        Text("\(learned)/\(total) learned")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
            } footer: {
                Text("Teach the app your amplifier's remote so power, input, and volume can be controlled from here.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private var profileSection: some View {
        Section {
            Picker("Profile", selection: $selectedProfileId) {
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            if selectedProfileId != (model.activeProfileId ?? "") {
                Button("Activate") { Task { await model.activate(profileId: selectedProfileId) } }
            }
            Button("Save Current as New Profile…") {
                newProfileName = ""
                showSaveProfileSheet = true
            }
            Button("Export Selected Profile") { Task { await export() } }
            Button("Import Profile…") { showImporter = true }
            if let profile = model.profiles.first(where: { $0.id == selectedProfileId }), profile.origin != "builtin" {
                Button("Delete Selected Profile", role: .destructive) {
                    Task { await model.deleteProfile(id: profile.id) }
                }
            }
        } header: {
            Text("Profile")
        }
    }

    private var saveProfileSheet: some View {
        NavigationStack {
            Form {
                TextField("Profile Name", text: $newProfileName)
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveProfileSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveAsNewProfile(id: slugify(newProfileName), name: newProfileName)
                            showSaveProfileSheet = false
                        }
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func seed(from config: RigAmplifierConfig?) {
        guard let config else { return }
        maker = config.maker ?? ""
        deviceModel = config.model ?? ""
        inputMode = config.inputMode ?? "cycle"
        warmUpSecs = config.warmUpSecs.map(String.init) ?? ""
        standbyTimeoutMins = config.standbyTimeoutMins.map(String.init) ?? ""
        inputs = config.inputs ?? []
        if selectedProfileId.isEmpty {
            selectedProfileId = model.activeProfileId ?? config.profileId ?? ""
        }
    }

    private func save() async {
        let outboundInputs = inputs.map { input -> RigInputConfig in
            var i = input
            if i.id.hasPrefix("_new_") { i.id = "" }
            return i
        }
        let patch = RigAmplifierConfig(
            profileId: nil,
            maker: maker.nonEmpty,
            model: deviceModel.nonEmpty,
            inputMode: inputMode,
            warmUpSecs: Int(warmUpSecs),
            standbyTimeoutMins: Int(standbyTimeoutMins),
            cycle: model.config?.cycle,
            inputs: outboundInputs
        )
        await model.save(patch)
    }

    private func export() async {
        guard let doc = await model.exportProfile(id: selectedProfileId) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(doc)
            exportDocument = AmplifierProfileDocument(data: data)
            showExporter = true
        } catch {
            model.actionError = "Couldn't prepare the export."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        guard case let .success(url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let doc = try decoder.decode(RigProfileExportDoc.self, from: data)
            await model.importProfile(doc)
        } catch {
            model.actionError = "Couldn't read that profile file."
        }
    }
}

private func slugify(_ text: String) -> String {
    let lowered = text.lowercased()
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
    let mapped = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    return String(mapped)
}
