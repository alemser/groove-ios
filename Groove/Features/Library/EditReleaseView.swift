import SwiftUI
import PhotosUI

/// Full metadata editor for an owned release — device attributes, tracklist,
/// and artwork — mirroring the web studio's release editor. Edits in place
/// when the release has a `catalog_job_id`; otherwise the only backend path
/// is a fresh editable copy, which this screen discloses up front. Also
/// doubles as the second half of "Add Release" (`AddReleaseView`), opened via
/// `init(jobId:draft:)` once a scratch release has been created.
struct EditReleaseView: View {
    /// `nil` when editing a release just created from scratch through the
    /// standalone "Add Release" flow — nothing to detach tracks from, and no
    /// "editing creates a copy" caveat applies.
    let release: LibraryRelease?
    var onSaved: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditReleaseModel

    @State private var album = ""
    @State private var artist = ""
    @State private var label = ""
    @State private var country = ""
    @State private var releaseDate = ""
    @State private var releaseType = ""
    @State private var releaseFormat = "vinyl"
    @State private var notes = ""
    @State private var tracklist: [TracklistEntry] = []

    @State private var artworkItem: PhotosPickerItem?
    @State private var artworkPreview: Image?

    @State private var showDetachConfirm = false
    @State private var showForcePublish = false
    @State private var didSeed = false

    init(release: LibraryRelease, onSaved: @escaping () -> Void = {}) {
        self.release = release
        self.onSaved = onSaved
        _model = State(initialValue: EditReleaseModel(release: release))
    }

    /// Opens straight into a release just created from scratch — the "cadastro"
    /// path from `AddReleaseView`, which already has a draft + jobId in hand.
    init(jobId: Int64, draft: PendingRelease, onSaved: @escaping () -> Void = {}) {
        self.release = nil
        self.onSaved = onSaved
        _model = State(initialValue: EditReleaseModel(jobId: jobId, draft: draft))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    LoadingView(label: "Loading release…")
                case let .error(message):
                    ErrorStateView(message: message) { Task { await model.load() } }
                case .loaded:
                    form
                }
            }
            .grooveScreenBackground()
            .navigationTitle(release == nil ? "New Release" : "Edit Release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isSaving ? "Saving…" : "Save Draft") { Task { await saveDraft() } }
                        .disabled(model.isSaving || model.isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isPublishing ? "Publishing…" : "Publish") { Task { await publish() } }
                        .disabled(model.isSaving || model.isPublishing)
                }
            }
        }
        .task { model.configure(settings) }
        // `init(jobId:draft:)` starts with `model.draft` already set — no
        // transition ever happens for `onChange` below to catch, so the form
        // would stay blank without this explicit first pass.
        .task { seed(from: model.draft) }
        .onChange(of: model.draft) { _, new in seed(from: new) }
        .onChange(of: artworkItem) { _, item in
            guard let item else { return }
            Task { await uploadPickedArtwork(item) }
        }
    }

    private var form: some View {
        Form {
            if model.isCopy {
                Section {
                    Label(
                        "Editing creates a copy in your library — the original release stays untouched.",
                        systemImage: "doc.on.doc"
                    )
                    .font(.footnote)
                    .foregroundStyle(Brand.warn)
                }
            }

            Section("Artwork") {
                artworkRow
            }

            Section("Release") {
                TextField("Album", text: $album)
                TextField("Artist", text: $artist)
                TextField("Label", text: $label)
                TextField("Country", text: $country)
                TextField("Release Date (YYYY-MM-DD)", text: $releaseDate)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Release Type (e.g. studio, compilation)", text: $releaseType)
                Picker("Format", selection: $releaseFormat) {
                    Text("Vinyl").tag("vinyl")
                    Text("CD").tag("cd")
                    Text("Cassette").tag("cassette")
                    Text("Digital").tag("digital")
                    Text("Mixed").tag("mixed")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            tracklistSection

            if let error = model.actionError {
                Section {
                    Text(error).foregroundStyle(Brand.err)
                    if showForcePublish {
                        Button("Force Publish Anyway", role: .destructive) {
                            Task { await publish(force: true) }
                        }
                    }
                }
            }

            if release != nil {
                Section {
                    Button("Detach All Tracks", role: .destructive) { showDetachConfirm = true }
                } footer: {
                    Text("Unlinks every catalog track from this edition. The edition and its tracklist stay in your library so you can rebuild it later.")
                        .foregroundStyle(Brand.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Detach all tracks from this release?",
            isPresented: $showDetachConfirm,
            titleVisibility: .visible
        ) {
            Button("Detach", role: .destructive) { Task { await model.detachTracks() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artworkRow: some View {
        HStack(spacing: 14) {
            Group {
                if let artworkPreview {
                    artworkPreview.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Artwork(raw: model.draft?.artworkUrl, cornerRadius: 10)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            PhotosPicker(selection: $artworkItem, matching: .images) {
                if model.isUploadingArtwork {
                    HStack { ProgressView(); Text("Uploading…") }
                } else {
                    Text("Choose Photo")
                }
            }
            .disabled(model.isUploadingArtwork)
            Spacer()
        }
    }

    @ViewBuilder
    private var tracklistSection: some View {
        Section {
            ForEach($tracklist) { $entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Pos", text: Binding(get: { entry.position ?? "" }, set: { entry.position = $0.nonEmpty }))
                            .frame(width: 44)
                        TextField("Title", text: Binding(get: { entry.title ?? "" }, set: { entry.title = $0.nonEmpty }))
                    }
                    HStack(spacing: 8) {
                        TextField("ISRC", text: Binding(get: { entry.isrc ?? "" }, set: { entry.isrc = $0.nonEmpty }))
                            .font(.caption)
                        Spacer()
                        TextField("m:ss", text: durationBinding(for: entry))
                            .font(.caption.monospacedDigit())
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, 4)
            }
            .onMove { indices, newOffset in
                tracklist.move(fromOffsets: indices, toOffset: newOffset)
                renumber()
            }
            .onDelete { offsets in
                tracklist.remove(atOffsets: offsets)
                renumber()
            }

            Button {
                let nextOrdinal = (tracklist.map(\.ordinal).max() ?? 0) + 1
                tracklist.append(TracklistEntry(position: nil, ordinal: nextOrdinal, isrc: nil, title: "New Track", durationMs: nil))
            } label: {
                Label("Add Track", systemImage: "plus")
            }
        } header: {
            Text("Tracklist")
        } footer: {
            Text("Drag to reorder; the play order is saved alongside position labels like \"A1\".")
                .foregroundStyle(Brand.muted)
        }
    }

    private func durationBinding(for entry: TracklistEntry) -> Binding<String> {
        Binding(
            get: { Format.duration(entry.durationMs) },
            set: { newValue in
                guard let index = tracklist.firstIndex(where: { $0.ordinal == entry.ordinal }) else { return }
                tracklist[index].durationMs = parseDuration(newValue)
            }
        )
    }

    private func parseDuration(_ text: String) -> Int64? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
        return Int64((m * 60 + s) * 1000)
    }

    private func renumber() {
        for index in tracklist.indices {
            tracklist[index].ordinal = index + 1
        }
    }

    private func seed(from draft: PendingRelease?) {
        guard let draft, !didSeed else { return }
        didSeed = true
        album = draft.album ?? ""
        artist = draft.artist ?? ""
        label = draft.label ?? ""
        country = draft.country ?? ""
        releaseDate = draft.releaseDate ?? ""
        releaseType = draft.releaseType ?? ""
        releaseFormat = draft.releaseFormat?.lowercased().nonEmpty ?? "vinyl"
        tracklist = (draft.tracklist ?? []).sorted { $0.ordinal < $1.ordinal }
    }

    private func buildPatch() -> UserReleaseDraftPatch {
        var patch = UserReleaseDraftPatch()
        patch.album = album
        patch.artist = artist
        patch.label = label
        patch.country = country
        patch.releaseDate = releaseDate
        patch.releaseType = releaseType
        patch.releaseFormat = releaseFormat
        patch.notes = notes
        patch.tracklist = tracklist
        return patch
    }

    private func saveDraft() async {
        await model.saveDraft(buildPatch())
    }

    private func publish(force: Bool = false) async {
        _ = await model.saveDraft(buildPatch())
        let ok = await model.publish(force: force)
        if ok {
            onSaved()
            dismiss()
        } else {
            showForcePublish = true
        }
    }

    private func uploadPickedArtwork(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        artworkPreview = Image(uiImage: UIImage(data: data) ?? UIImage())
        _ = await model.uploadArtwork(data, filename: "artwork.jpg", mimeType: "image/jpeg")
    }
}
