import SwiftUI

struct ReleaseDetailView: View {
    let release: LibraryRelease

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Artwork(raw: release.artworkUrl, cornerRadius: 18)
                    .frame(maxWidth: 260)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(release.album)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.text)
                    Text(release.artist)
                        .font(.title3)
                        .foregroundStyle(Brand.teal)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    if release.owned { Badge(text: "Owned", color: Brand.ok, filled: true) }
                    if let media = Format.mediaFormat(release.releaseFormat) { Badge(text: media, color: Brand.gold) }
                    Badge(text: release.source, color: Brand.muted)
                }

                VStack(spacing: 0) {
                    if let year = release.year?.nonEmpty { InfoRow(label: "Year", value: year); Divider().overlay(Brand.border) }
                    if let label = release.label?.nonEmpty { InfoRow(label: "Label", value: label); Divider().overlay(Brand.border) }
                    if let country = release.country?.nonEmpty { InfoRow(label: "Country", value: country); Divider().overlay(Brand.border) }
                    InfoRow(label: "Tracklist", value: "\(release.tracklistCount) tracks")
                    Divider().overlay(Brand.border)
                    InfoRow(label: "In catalog", value: "\(release.catalogTracks) tracks")
                    if let confirmed = release.confirmedAt {
                        Divider().overlay(Brand.border)
                        InfoRow(label: "Confirmed", value: Format.absolute(confirmed))
                    }
                }
                .padding(16)
                .grooveCard()

                if release.deletable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(deleting ? "Removing…" : "Remove from Library", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.err)
                    .disabled(deleting)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Brand.err).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .grooveScreenBackground()
        .navigationTitle(release.album)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this edition from your library?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Catalog metadata is preserved; only this library edition is removed.")
        }
    }

    private func delete() async {
        deleting = true
        errorMessage = nil
        do {
            try await CatalogService(settings: settings).deleteLibraryRelease(source: release.source, releaseId: release.releaseId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            deleting = false
        }
    }
}
