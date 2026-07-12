import SwiftUI

struct LibraryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case releases = "Releases"
        case tracks = "Tracks"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .releases

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch segment {
                case .releases: ReleasesView()
                case .tracks: TracksView()
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Int64.self) { trackId in
                TrackDetailView(trackId: trackId)
            }
            .navigationDestination(for: LibraryRelease.self) { release in
                ReleaseDetailView(release: release)
            }
            .grooveScreenBackground()
        }
    }
}
