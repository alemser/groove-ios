import SwiftUI

/// Host/API key/secret for one built-in recognition provider (ACRCloud,
/// AudD). Secrets arrive redacted (`••••••••`); leaving a field showing that
/// placeholder untouched keeps the existing value on save.
struct ProviderCredentialsView: View {
    let providerID: String
    let model: RecognitionProvidersModel

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host (if required)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key", text: $apiKey)
                    SecureField("API Secret", text: $apiSecret)
                } footer: {
                    Text("Leave a field showing •••••••• unchanged to keep its current value.")
                        .foregroundStyle(Brand.muted)
                }

                if let error = model.actionError {
                    Section {
                        Text(error).foregroundStyle(Brand.err)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle(providerID.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .onAppear(perform: loadFields)
    }

    private func loadFields() {
        let builtin = model.state?.builtins[providerID]
        host = builtin?.host ?? ""
        apiKey = builtin?.apiKey ?? ""
        apiSecret = builtin?.apiSecret ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ok = await model.saveCredentials(
            id: providerID,
            host: host.nonEmpty,
            apiKey: apiKey.nonEmpty,
            apiSecret: apiSecret.nonEmpty
        )
        if ok { dismiss() }
    }
}
