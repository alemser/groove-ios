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
    @State private var useInputForFormat = true

    @State private var selectedProfileId = ""
    @State private var showDuplicateSheet = false
    @State private var duplicateName = ""
    @State private var confirmReset = false
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
        .onChange(of: model.useAmplifierInputForFormat) { _, new in useInputForFormat = new }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(model.isSaving)
            }
        }
        .sheet(isPresented: $showDuplicateSheet) { duplicateSheet }
        .confirmationDialog(
            "Reset to factory settings?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await model.resetProfile(id: selectedProfileId) }
            }
        } message: {
            Text("Your input names, visibility and timing for this amplifier are discarded. Learned remote codes are kept.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "amplifier-profile") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            Task { await handleImport(result) }
        }
    }

    private var content: some View {
        Form {
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
                Toggle("Use Input to Detect Format", isOn: $useInputForFormat)
            } footer: {
                Text("When an album is in your catalogue on more than one format, the input this amplifier is switched to decides which one is playing — PHONO means the record. Turn this off if you change inputs by hand: the rig only knows the input it set itself, so a stale one would answer confidently and wrongly.")
                    .foregroundStyle(Brand.muted)
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

    private var selectedProfile: RigStoredAmplifierProfile? {
        model.profiles.first { $0.id == selectedProfileId }
    }

    /// Edits are saved into the active profile (a built-in's override, or
    /// the custom profile) by groove-rig itself, so there's no "save as new
    /// profile" step — Duplicate is the only thing that makes a copy.
    private var profileSection: some View {
        let isActive = selectedProfileId == (model.activeProfileId ?? "")
        return Section {
            Picker("Profile", selection: $selectedProfileId) {
                ForEach(model.profiles) { profile in
                    Text(profile.customised == true ? "\(profile.name) · customised" : profile.name).tag(profile.id)
                }
            }
            if !isActive {
                Button("Activate") { Task { await model.activate(profileId: selectedProfileId) } }
            }
            if let profile = selectedProfile, profile.origin == "builtin", profile.customised == true {
                Button("Reset to Factory Settings") { confirmReset = true }
            }
            Button("Duplicate Selected Profile…") {
                duplicateName = "\(selectedProfile?.name ?? "Amplifier") (copy)"
                showDuplicateSheet = true
            }
            Button("Export Selected Profile") { Task { await export() } }
            Button("Import Profile…") { showImporter = true }
            if let profile = selectedProfile, profile.origin != "builtin", !isActive {
                Button("Delete Selected Profile", role: .destructive) {
                    Task { await model.deleteProfile(id: profile.id) }
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text(isActive
                 ? "Changes you save below are kept with this amplifier — switching to another one and back brings them back."
                 : "Activating switches the rig to this amplifier, with its own settings, remote codes and equipment wiring.")
                .foregroundStyle(Brand.muted)
        }
    }

    private var duplicateSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Profile Name", text: $duplicateName)
                } footer: {
                    Text("The copy keeps this profile's learned remote codes and equipment wiring.")
                        .foregroundStyle(Brand.muted)
                }
            }
            .navigationTitle("Duplicate Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDuplicateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate") {
                        Task {
                            guard let source = selectedProfile else { return }
                            let name = duplicateName.trimmingCharacters(in: .whitespaces)
                            if let id = await model.duplicateProfile(source, name: name) {
                                selectedProfileId = id
                            }
                            showDuplicateSheet = false
                        }
                    }
                    .disabled(duplicateName.trimmingCharacters(in: .whitespaces).isEmpty)
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
        useInputForFormat = model.useAmplifierInputForFormat
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
        await model.save(patch, useAmplifierInputForFormat: useInputForFormat)
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
