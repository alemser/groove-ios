import SwiftUI

/// Per-provider credential fields for a metadata enricher — mirrors the
/// catalog studio's hardcoded field set exactly: MusicBrainz needs a contact
/// email, Discogs a personal access token, iTunes a storefront country and
/// result limit.
struct EnricherCredentialsForm: View {
    let providerID: String
    let model: EnricherSettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var contact = ""
    @State private var apiKey = ""
    @State private var country = ""
    @State private var limit = ""
    @State private var isSaving = false

    private var canSave: Bool {
        switch providerID {
        case "musicbrainz": return contact.nonEmpty != nil && !isSaving
        default: return !isSaving
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                fields

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
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: loadFields)
    }

    @ViewBuilder
    private var fields: some View {
        switch providerID {
        case "musicbrainz":
            Section {
                TextField("Contact email", text: $contact)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } footer: {
                Text("MusicBrainz requires a contact email in the API user agent.")
                    .foregroundStyle(Brand.muted)
            }
        case "discogs":
            Section {
                SecureField("Personal access token", text: $apiKey)
            } footer: {
                Text("Leave blank to keep the current token.")
                    .foregroundStyle(Brand.muted)
            }
        case "itunes":
            Section {
                TextField("Country (ISO, e.g. US)", text: $country)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Result limit", text: $limit)
                    .keyboardType(.numberPad)
            }
        default:
            EmptyView()
        }
    }

    private func loadFields() {
        guard let slot = model.chain.first(where: { $0.id == providerID }) else { return }
        contact = slot.params?["contact"] ?? ""
        country = slot.params?["country"] ?? ""
        limit = slot.params?["limit"] ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var params: [String: String] = [:]
        var key: String?
        switch providerID {
        case "musicbrainz":
            guard let c = contact.nonEmpty else { return }
            params["contact"] = c
        case "discogs":
            key = apiKey.nonEmpty
        case "itunes":
            if let c = country.nonEmpty { params["country"] = c.uppercased() }
            if let l = limit.nonEmpty { params["limit"] = l }
        default:
            break
        }
        let ok = await model.saveCredentials(id: providerID, apiKey: key, params: params.isEmpty ? nil : params)
        if ok { dismiss() }
    }
}
