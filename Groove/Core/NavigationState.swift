import SwiftUI
import Observation

/// Cross-tab UI state: which tab is active, the global Now Playing sheet, and
/// the screens a notification tap opens from outside their tab. App-owned (like
/// `AppSettings`/`AttentionCenter`) so the tab bar, the persistent mini-bar,
/// Home's summary card and the notification delegate can all reach them without
/// threading callbacks through view hierarchies.
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
    var isAssociationReviewPresented = false
    var isStylusPresented = false

    init() {
        let stored = defaults.string(forKey: Self.selectedTabKey).flatMap(Tab.init(rawValue:))
        selectedTab = stored ?? .home
    }

    func openNowPlaying() {
        isNowPlayingSheetPresented = true
    }

    func open(_ destination: NotificationDestination) {
        // An app-wide sheet left open would cover the destination.
        isNowPlayingSheetPresented = false
        isAssociationReviewPresented = false
        switch destination {
        case .associations:
            selectedTab = .library
            isAssociationReviewPresented = true
        case .stylus:
            selectedTab = .rig
            isStylusPresented = true
        }
    }
}
