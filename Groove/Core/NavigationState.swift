import SwiftUI
import Observation

/// Cross-tab UI state: which tab is active and whether the global Now Playing
/// sheet is presented. App-owned (like `AppSettings`/`AttentionCenter`) so the tab
/// bar, the persistent mini-bar, and Home's summary card can all open the same
/// sheet without threading callbacks through view hierarchies.
@Observable
final class NavigationState {
    enum Tab: String, Hashable {
        case home, library, rig, settings
    }

    private let defaults = UserDefaults.standard
    private static let selectedTabKey = "selectedTab"

    var selectedTab: Tab {
        didSet { defaults.set(selectedTab.rawValue, forKey: Self.selectedTabKey) }
    }

    var isNowPlayingSheetPresented = false

    init() {
        let stored = defaults.string(forKey: Self.selectedTabKey).flatMap(Tab.init(rawValue:))
        selectedTab = stored ?? .home
    }

    func openNowPlaying() {
        isNowPlayingSheetPresented = true
    }
}
