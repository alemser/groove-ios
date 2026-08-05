import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ReleasesView()
                .navigationTitle("Library")
                .navigationDestination(for: Int64.self) { trackId in
                    TrackDetailView(trackId: trackId)
                }
                .navigationDestination(for: LibraryRelease.self) { release in
                    ReleaseDetailView(release: release)
                }
                .navigationDestination(for: EnrichJob.self) { job in
                    EnrichJobDetailView(job: job)
                }
                .grooveScreenBackground()
        }
    }
}
