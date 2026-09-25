import SwiftUI
import Observation

@MainActor
@Observable
final class AddReleaseModel {
    var results: [IdentifySearchHit] = []
    var phase: Phase = .idle
    var busyId: String?
    var actionError: String?

    enum Phase: Equatable { case idle, loading, loaded, error(String) }

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        self.settings = settings
    }

    /// Explicit lookup, fired only when the user taps Search (or submits a
    /// field) — not per keystroke. Mirrors the web studio's "Lookup using
    /// enrichers": a barcode (typed or scanned) names one exact pressing and
    /// wins outright — same precedence identify/search itself applies server
    /// side — otherwise falls back to the separate Artist/Album fields.
    func search(artist: String, album: String, barcode: String) {
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let barcodeDigits = Barcode.digits(from: barcode)
        guard !barcodeDigits.isEmpty || !artist.isEmpty || !album.isEmpty, let settings else {
            phase = .idle; results = []; return
        }
        Task {
            phase = .loading
            do {
                // A wider net than the default 25: the filters below only ever
                // narrow what came back, so a pressing that fell outside the
                // page can never be filtered into view.
                let service = CatalogService(settings: settings)
                results = barcodeDigits.isEmpty
                    ? try await service.identifySearch(artist: artist, album: album, limit: 40)
                    : try await service.identifySearch(barcode: barcodeDigits, limit: 40)
                phase = .loaded
            } catch {
                phase = .error(error.localizedForDisplay)
            }
        }
    }

    /// The form for a new release, prefilled from a picked search hit's
    /// metadata and tracklist. Writes nothing — the release is created when
    /// the editor saves.
    func prefill(from hit: IdentifySearchHit) async -> PendingRelease? {
        guard let settings else { return nil }
        busyId = hit.id
        actionError = nil
        defer { busyId = nil }
        do {
            return try await CatalogService(settings: settings).prefillUserRelease(from: hit)
        } catch {
            actionError = error.localizedForDisplay
            return nil
        }
    }
}

/// The "cadastro" entry point: Artist + Album fields up front, mirroring the
/// web studio's "New release" dialog — Search looks the pair up against
/// enrichers (only on an explicit tap, never per keystroke), or continue with
/// just what's typed. Either path hands off into `EditReleaseView` to fill in
/// format, tracklist, and artwork; nothing is written until it saves.
struct AddReleaseView: View {
    let onCreated: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var model = AddReleaseModel()
    @State private var artist = ""
    @State private var album = ""
    @State private var barcode = ""
    @State private var showScanner = false
    @State private var newRelease: NewRelease?
    @State private var selectedFormat: String?
    @State private var selectedCountry: String?

    private enum Field { case artist, album, barcode }

    private var hasQuery: Bool {
        !Barcode.digits(from: barcode).isEmpty
            || !artist.trimmingCharacters(in: .whitespaces).isEmpty
            || !album.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canCreate: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty && !album.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Barcode (EAN/UPC)", text: $barcode)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .barcode)
                            .submitLabel(.search)
                            .onSubmit { search() }
                        Button {
                            focusedField = nil
                            showScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Artist", text: $artist)
                        .focused($focusedField, equals: .artist)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .album }
                    TextField("Album", text: $album)
                        .focused($focusedField, equals: .album)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    Button {
                        search()
                    } label: {
                        HStack {
                            Spacer()
                            if model.phase == .loading { ProgressView() }
                            Text("Search")
                            Spacer()
                        }
                    }
                    .disabled(!hasQuery || model.phase == .loading)
                } footer: {
                    Text("A barcode names the exact pressing and skips artist/album — type it, scan it, or search by artist and album instead.")
                        .foregroundStyle(Brand.muted)
                }

                filterSection
                resultsSection

                Section {
                    Button {
                        continueManually()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Continue Without Searching")
                            Spacer()
                        }
                    }
                    .disabled(!canCreate)
                }

                if let err = model.actionError {
                    Section {
                        Text(err).foregroundStyle(Brand.err)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Add Release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $newRelease) { item in
                EditReleaseView(newRelease: item.prefill, from: item.hit) {
                    onCreated()
                    dismiss()
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { scanned in
                    barcode = scanned
                    search()
                }
            }
        }
        .task { model.configure(settings) }
        .onAppear { focusedField = .barcode }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            Section { LoadingView() }.listRowBackground(Color.clear)
        case let .error(message):
            Section { ErrorStateView(message: message) { search() } }
        case .loaded:
            if model.results.isEmpty {
                Section {
                    Text("No matches. You can still continue with just artist and album below.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            } else if filteredResults.isEmpty {
                Section {
                    Text("No result matches those filters. The pressing you want may not be in the providers — clear the filters to see everything that came back, or continue with just artist and album below.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                    Button("Clear filters") { selectedFormat = nil; selectedCountry = nil }
                }
            } else {
                Section("Results") {
                    ForEach(filteredResults) { hit in
                        Button {
                            Task { await createFromHit(hit) }
                        } label: {
                            IdentifyHitRow(hit: hit, busy: model.busyId == hit.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busyId != nil)
                        .listRowBackground(Brand.surface)
                    }
                }
            }
        }
    }

    /// One value a result can be filtered by, with how many results carry it.
    private struct FilterOption: Identifiable, Hashable {
        let key: String
        let label: String
        let count: Int
        var id: String { key }
    }

    /// Options are built from what the search actually returned, never from a
    /// fixed list of countries and formats. Two reasons: every option offered
    /// is guaranteed to leave at least one result, and the ABSENCE of an option
    /// is itself the answer — no "Vinyl" in the list means the providers hold
    /// no vinyl pressing of this record, which is what the operator wanted to
    /// know before typing one in by hand.
    private func options(_ value: (IdentifySearchHit) -> String?) -> [FilterOption] {
        var counts: [String: (label: String, n: Int)] = [:]
        for hit in model.results {
            let raw = (value(hit) ?? "").trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let key = raw.lowercased()
            counts[key] = (counts[key]?.label ?? raw, (counts[key]?.n ?? 0) + 1)
        }
        return counts
            .map { FilterOption(key: $0.key, label: $0.value.label, count: $0.value.n) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }

    private var formatOptions: [FilterOption] { options(\.releaseFormat) }
    private var countryOptions: [FilterOption] { options(\.country) }

    private var filteredResults: [IdentifySearchHit] {
        model.results.filter { hit in
            let f = (hit.releaseFormat ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let c = (hit.country ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return (selectedFormat == nil || f == selectedFormat)
                && (selectedCountry == nil || c == selectedCountry)
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        if model.phase == .loaded, formatOptions.count > 1 || countryOptions.count > 1 {
            Section {
                if formatOptions.count > 1 {
                    Picker("Format", selection: $selectedFormat) {
                        Text("Any").tag(String?.none)
                        ForEach(formatOptions) { o in
                            Text("\(o.label) (\(o.count))").tag(String?.some(o.key))
                        }
                    }
                }
                if countryOptions.count > 1 {
                    Picker("Country", selection: $selectedCountry) {
                        Text("Any").tag(String?.none)
                        ForEach(countryOptions) { o in
                            Text("\(o.label) (\(o.count))").tag(String?.some(o.key))
                        }
                    }
                }
            } header: {
                Text("Narrow the results")
            } footer: {
                Text("Only what this search returned is offered. A format or country missing from these lists means the providers hold no such pressing of this record.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private func search() {
        focusedField = nil
        // A new search is a new set of results; carrying the old filters over
        // would silently hide most of it.
        selectedFormat = nil
        selectedCountry = nil
        model.search(artist: artist, album: album, barcode: barcode)
    }

    private func createFromHit(_ hit: IdentifySearchHit) async {
        guard let prefill = await model.prefill(from: hit) else { return }
        newRelease = NewRelease(prefill: prefill, hit: hit)
    }

    private func continueManually() {
        let prefill = PendingRelease(
            id: 0, jobId: 0, status: "",
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        newRelease = NewRelease(prefill: prefill, hit: nil)
    }
}

/// The form a new release opens with. Not stored anywhere — the release
/// exists once the editor saves it.
private struct NewRelease: Identifiable {
    let id = UUID()
    let prefill: PendingRelease
    let hit: IdentifySearchHit?
}
