import SwiftUI

/// Create or edit a custom HTTP recognition provider — any service that takes
/// an audio POST and returns JSON. Mirrors the web studio's editor: typed
/// fields for everything, plus a "paste a sample response" shortcut that
/// auto-fills the response field mapping.
struct CustomProviderFormView: View {
    let existing: CustomProviderConfig?
    let model: RecognitionProvidersModel

    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var displayName = ""
    @State private var endpointUrl = ""
    @State private var authMode: CustomProviderAuthMode = .headerToken
    @State private var token = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var tokenHeader = ""
    @State private var tokenField = ""
    @State private var keyField = ""
    @State private var secretField = ""
    @State private var keyHeader = ""
    @State private var secretHeader = ""

    @State private var audioField = "file"
    @State private var timeoutSecs = "10"

    @State private var matchPath = ""
    @State private var titleField = ""
    @State private var artistField = ""
    @State private var albumField = ""
    @State private var scoreField = ""
    @State private var durationField = ""
    @State private var offsetField = ""
    @State private var isrcField = ""

    @State private var sampleText = ""
    @State private var isAnalyzing = false
    @State private var analyzeMessage: String?

    @State private var isSaving = false
    @State private var error: String?
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        !id.trimmingCharacters(in: .whitespaces).isEmpty &&
        !endpointUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                authSection
                requestSection
                responseSection
                sampleSection

                if let error {
                    Section { Text(error).foregroundStyle(Brand.err) }
                }

                if isEditing {
                    Section {
                        Button("Delete Provider", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle(isEditing ? "Edit Provider" : "New Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this provider?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let slug = existing?.id { await model.deleteCustomProvider(slug: slug) }
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear(perform: loadFields)
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            if isEditing {
                LabeledContent("ID", value: id)
            } else {
                TextField("id (lowercase, e.g. myservice)", text: $id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            TextField("Display Name", text: $displayName)
            TextField("Endpoint URL", text: $endpointUrl)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } header: {
            Text("Identity")
        }
    }

    @ViewBuilder
    private var authSection: some View {
        Section {
            Picker("Auth Mode", selection: $authMode) {
                ForEach(CustomProviderAuthMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            switch authMode {
            case .bearerToken:
                SecureField("Token", text: $token)
            case .headerToken:
                SecureField("Token", text: $token)
                TextField("Token Header (default X-API-Key)", text: $tokenHeader)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .headerKeySecret:
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
                TextField("Key Header (default X-API-Key)", text: $keyHeader)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Secret Header (default X-API-Secret)", text: $secretHeader)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .formToken:
                SecureField("Token", text: $token)
                TextField("Token Field (default api_token)", text: $tokenField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .formKeySecret:
                SecureField("API Key", text: $apiKey)
                SecureField("API Secret", text: $apiSecret)
                TextField("Key Field (default api_key)", text: $keyField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Secret Field (default api_secret)", text: $secretField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Authentication")
        } footer: {
            if isEditing {
                Text("Leave a secret field blank to keep its current value.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private var requestSection: some View {
        Section {
            TextField("Audio Field", text: $audioField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Timeout (secs)", text: $timeoutSecs)
                .keyboardType(.numberPad)
        } header: {
            Text("Request")
        }
    }

    private var responseSection: some View {
        Section {
            TextField("Match Path (e.g. result)", text: $matchPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Title field", text: $titleField)
            TextField("Artist field", text: $artistField)
            TextField("Album field", text: $albumField)
            TextField("Score field", text: $scoreField)
            TextField("Duration (ms) field", text: $durationField)
            TextField("Match offset (ms) field", text: $offsetField)
            TextField("ISRC field", text: $isrcField)
        } header: {
            Text("Response Field Mapping")
        } footer: {
            Text("Dot paths into the JSON response, e.g. \"result.title\".")
                .foregroundStyle(Brand.muted)
        }
    }

    private var sampleSection: some View {
        Section {
            TextEditor(text: $sampleText)
                .frame(minHeight: 100)
                .font(.footnote.monospaced())
            Button {
                Task { await analyze() }
            } label: {
                HStack {
                    if isAnalyzing { ProgressView() }
                    Text(isAnalyzing ? "Analyzing…" : "Analyze")
                }
            }
            .disabled(sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
            if let analyzeMessage {
                Text(analyzeMessage).font(.caption).foregroundStyle(Brand.muted)
            }
        } header: {
            Text("Paste a Sample Response")
        } footer: {
            Text("Paste a real response from this provider and tap Analyze to auto-fill the match path and field mapping above — it only fills in fields you haven't already set.")
                .foregroundStyle(Brand.muted)
        }
    }

    // MARK: - Actions

    private func loadFields() {
        guard let cp = existing else { return }
        id = cp.id
        displayName = cp.displayName
        endpointUrl = cp.endpointUrl
        authMode = CustomProviderAuthMode(rawValue: cp.auth.mode) ?? .headerToken
        token = cp.auth.token ?? ""
        apiKey = cp.auth.apiKey ?? ""
        apiSecret = cp.auth.apiSecret ?? ""
        tokenHeader = cp.auth.tokenHeader ?? ""
        tokenField = cp.auth.tokenField ?? ""
        keyField = cp.auth.keyField ?? ""
        secretField = cp.auth.secretField ?? ""
        keyHeader = cp.auth.keyHeader ?? ""
        secretHeader = cp.auth.secretHeader ?? ""
        audioField = cp.request?.audioField?.nonEmpty ?? "file"
        timeoutSecs = cp.request?.timeoutSecs.map(String.init) ?? "10"
        matchPath = cp.response?.matchPath ?? ""
        titleField = cp.response?.fields?.title ?? ""
        artistField = cp.response?.fields?.artist ?? ""
        albumField = cp.response?.fields?.album ?? ""
        scoreField = cp.response?.fields?.score ?? ""
        durationField = cp.response?.fields?.durationMs ?? ""
        offsetField = cp.response?.fields?.matchOffsetMs ?? ""
        isrcField = cp.response?.fields?.isrc ?? ""
    }

    private func buildAuth() -> CustomProviderAuthConfig {
        CustomProviderAuthConfig(
            mode: authMode.rawValue,
            token: token.nonEmpty,
            apiKey: apiKey.nonEmpty,
            apiSecret: apiSecret.nonEmpty,
            tokenHeader: tokenHeader.nonEmpty,
            tokenField: tokenField.nonEmpty,
            keyField: keyField.nonEmpty,
            secretField: secretField.nonEmpty,
            keyHeader: keyHeader.nonEmpty,
            secretHeader: secretHeader.nonEmpty
        )
    }

    private func buildRequest() -> CustomProviderRequestConfig {
        CustomProviderRequestConfig(audioField: audioField.nonEmpty, timeoutSecs: Int(timeoutSecs))
    }

    private func buildResponse() -> CustomProviderResponseConfig {
        CustomProviderResponseConfig(
            matchPath: matchPath.nonEmpty,
            fields: CustomProviderFieldMap(
                title: titleField.nonEmpty,
                artist: artistField.nonEmpty,
                album: albumField.nonEmpty,
                score: scoreField.nonEmpty,
                durationMs: durationField.nonEmpty,
                matchOffsetMs: offsetField.nonEmpty,
                isrc: isrcField.nonEmpty
            )
        )
    }

    private func save() async {
        isSaving = true
        error = nil
        let slug = id.trimmingCharacters(in: .whitespaces).lowercased()
        if isEditing {
            let cp = CustomProviderConfig(
                id: slug, displayName: displayName.nonEmpty ?? slug, endpointUrl: endpointUrl,
                auth: buildAuth(), request: buildRequest(), response: buildResponse()
            )
            error = await model.updateCustomProvider(slug: slug, cp)
        } else {
            let req = CustomProviderCreateRequest(
                id: slug, displayName: displayName.nonEmpty ?? slug, endpointUrl: endpointUrl,
                auth: buildAuth(), request: buildRequest(), response: buildResponse(), enabled: true
            )
            error = await model.createCustomProvider(req)
        }
        isSaving = false
        if error == nil { dismiss() }
    }

    private func analyze() async {
        isAnalyzing = true
        analyzeMessage = nil
        defer { isAnalyzing = false }
        guard let data = sampleText.data(using: .utf8) else { return }
        do {
            let response = try await model.parseSample(slug: existing?.id, sampleJSON: data)
            guard response.inferred, let rec = response.recommended else {
                analyzeMessage = response.message ?? "Could not infer a field mapping from this sample."
                return
            }
            if matchPath.isEmpty { matchPath = rec.matchPath ?? matchPath }
            let fields = rec.fields
            if titleField.isEmpty { titleField = fields?.title ?? titleField }
            if artistField.isEmpty { artistField = fields?.artist ?? artistField }
            if albumField.isEmpty { albumField = fields?.album ?? albumField }
            if scoreField.isEmpty { scoreField = fields?.score ?? scoreField }
            if durationField.isEmpty { durationField = fields?.durationMs ?? durationField }
            if offsetField.isEmpty { offsetField = fields?.matchOffsetMs ?? offsetField }
            if isrcField.isEmpty { isrcField = fields?.isrc ?? isrcField }
            analyzeMessage = "Applied suggested field mapping."
        } catch {
            analyzeMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
