import SwiftUI

/// Sheet for setting user display overrides and the media format on a track.
struct EditTrackView: View {
    let track: Track
    let onSave: (TrackDisplayPatch) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var artist: String
    @State private var title: String
    @State private var album: String
    @State private var format: String
    @State private var saving = false

    private static let formats = ["", "vinyl", "cd", "digital", "cassette"]

    init(track: Track, onSave: @escaping (TrackDisplayPatch) async -> Bool) {
        self.track = track
        self.onSave = onSave
        _artist = State(initialValue: track.artist ?? "")
        _title = State(initialValue: track.title ?? "")
        _album = State(initialValue: track.album ?? "")
        _format = State(initialValue: (track.userReleaseFormat ?? track.releaseFormat ?? "").lowercased())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Names") {
                    labeled("Title", text: $title, placeholder: track.providerTitle)
                    labeled("Artist", text: $artist, placeholder: track.providerArtist)
                    labeled("Album", text: $album, placeholder: track.providerAlbum)
                }

                Section("Media Format") {
                    Picker("Format", selection: $format) {
                        Text("Auto").tag("")
                        Text("Vinyl").tag("vinyl")
                        Text("CD").tag("cd")
                        Text("Digital").tag("digital")
                        Text("Cassette").tag("cassette")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Leave a field empty to fall back to the provider's value.")
                        .font(.footnote)
                        .foregroundStyle(Brand.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Edit Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
    }

    private func labeled(_ label: String, text: Binding<String>, placeholder: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.muted).frame(width: 64, alignment: .leading)
            TextField(placeholder?.nonEmpty ?? label, text: text)
                .foregroundStyle(Brand.text)
        }
    }

    private func save() async {
        saving = true
        let patch = TrackDisplayPatch(
            displayArtist: artist.trimmingCharacters(in: .whitespaces),
            displayTitle: title.trimmingCharacters(in: .whitespaces),
            displayAlbum: album.trimmingCharacters(in: .whitespaces),
            releaseFormat: format,
            reset: false
        )
        if await onSave(patch) {
            dismiss()
        } else {
            saving = false
        }
    }
}
