import SwiftUI
import Observation

/// Whether a search hit's edition has every track's duration, which confirming it needs.
enum TrackTimes {
    /// Not looked up yet: the search itself sends a tracklist for one hit at most.
    case unknown
    case checking
    case timed
    case untimed
    /// The provider didn't answer. The hit stays listed: nothing says it lacks times.
    case failed

    /// The answer is in: a lookup finished, or the search's own tracklist settled it.
    var isSettled: Bool { self != .unknown && self != .checking }

    /// The line under a result saying what is known, and its colour.
    var note: (text: String?, color: Color) {
        switch self {
        case .unknown: return (nil, Brand.muted)
        case .checking: return ("Checking track times…", Brand.muted)
        case .timed: return ("Every track timed", Brand.ok)
        case .untimed: return ("No track times", Brand.warn)
        case .failed: return ("Couldn't check track times", Brand.muted)
        }
    }
}

@MainActor
@Observable
final class AddReleaseModel {
    var results: [IdentifySearchHit] = []
    var phase: Phase = .idle
    var busyId: String?

    enum Phase: Equatable { case idle, loading, loaded, error(String) }

    private var settings: AppSettings?
    private var messages: MessageCenter?
    /// What a lookup found, by hit id; a hit missing here is judged by its own tracklist.
    private var lookedUp: [String: TrackTimes] = [:]
    /// Lookups already made, so picking a checked hit doesn't ask the provider again.
    @ObservationIgnored private var prefilled: [String: PendingRelease] = [:]

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        self.settings = settings
        self.messages = messages
    }

    func trackTimes(_ hit: IdentifySearchHit) -> TrackTimes {
        if let known = lookedUp[hit.id] { return known }
        guard let tracklist = hit.tracklist else { return .unknown }
        return hasTrackTimes(tracklist) ? .timed : .untimed
    }

    /// Looks up each hit whose times are unknown, one at a time: every lookup reaches the
    /// provider, within its rate limit. A cancelled lookup leaves its hit unknown.
    func checkTrackTimes(_ hits: [IdentifySearchHit]) async {
        guard let settings else { return }
        let service = CatalogService(settings: settings)
        for hit in hits where trackTimes(hit) == .unknown {
            if Task.isCancelled { return }
            lookedUp[hit.id] = .checking
            do {
                let release = try await service.prefillUserRelease(from: hit)
                prefilled[hit.id] = release
                lookedUp[hit.id] = hasTrackTimes(release.tracklist) ? .timed : .untimed
            } catch {
                lookedUp[hit.id] = Task.isCancelled ? nil : .failed
            }
        }
    }

    /// Explicit lookup, fired only when the user taps Search (or submits a
    /// field) — not per keystroke. Mirrors the web studio's "Lookup using
    /// enrichers": a barcode (typed or scanned) names one exact pressing and
    /// wins outright — same precedence identify/search itself applies server
    /// side — otherwise falls back to the separate Artist/Album fields.
    func search(artist: String, album: String, barcode: String) {
        lookedUp = [:]
        prefilled = [:]
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
        if let known = prefilled[hit.id] { return known }
        guard let settings, let messages else { return nil }
        busyId = hit.id
        defer { busyId = nil }
        return await messages.attempt { try await CatalogService(settings: settings).prefillUserRelease(from: hit) }
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
    @Environment(MessageCenter.self) private var messages
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
    @State private var onlyTimed = false

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
        .task { model.configure(settings, messages: messages) }
        // Off, or a format or country change, cancels the lookups; what they found is kept.
        .task(id: onlyTimed ? narrowedResults.map(\.id) : []) {
            if onlyTimed { await model.checkTrackTimes(narrowedResults) }
        }
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
                    Button("Clear filters") { clearFilters() }
                }
            } else {
                Section("Results") {
                    ForEach(filteredResults) { hit in
                        Button {
                            Task { await createFromHit(hit) }
                        } label: {
                            let note = model.trackTimes(hit).note
                            IdentifyHitRow(hit: hit, busy: model.busyId == hit.id, note: note.text, noteColor: note.color)
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

    private var narrowedResults: [IdentifySearchHit] {
        model.results.filter { hit in
            let f = (hit.releaseFormat ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let c = (hit.country ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return (selectedFormat == nil || f == selectedFormat)
                && (selectedCountry == nil || c == selectedCountry)
        }
    }

    /// A hit not looked up yet stays listed until its lookup says it has no times.
    private var filteredResults: [IdentifySearchHit] {
        guard onlyTimed else { return narrowedResults }
        return narrowedResults.filter { model.trackTimes($0) != .untimed }
    }

    private var showPickers: Bool { formatOptions.count > 1 || countryOptions.count > 1 }

    @ViewBuilder
    private var filterSection: some View {
        if model.phase == .loaded, !model.results.isEmpty {
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
                Toggle(isOn: $onlyTimed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only releases with track times")
                        Text(timedToggleSubtitle).font(.caption).foregroundStyle(Brand.muted)
                    }
                }
                .tint(Brand.accent)
            } header: {
                Text("Narrow the results")
            } footer: {
                Text(filterFooter).foregroundStyle(Brand.muted)
            }
        }
    }

    private var timedToggleSubtitle: String {
        let settled = narrowedResults.filter { model.trackTimes($0).isSettled }.count
        guard onlyTimed, settled < narrowedResults.count else {
            return "An edition without them has to be edited before it can be confirmed."
        }
        return "Checking \(settled) of \(narrowedResults.count)…"
    }

    private var filterFooter: String {
        let lookups = "Track times are looked up one release at a time, so the list narrows as they come in."
        guard showPickers else { return lookups }
        return "Only what this search returned is offered. A format or country missing from these lists means the providers hold no such pressing of this record. " + lookups
    }

    private func clearFilters() {
        selectedFormat = nil
        selectedCountry = nil
        onlyTimed = false
    }

    private func search() {
        focusedField = nil
        // A new search is a new set of results; carrying the old filters over
        // would silently hide most of it.
        clearFilters()
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
