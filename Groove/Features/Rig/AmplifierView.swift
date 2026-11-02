import SwiftUI

/// Hub for the amplifier: its own attributes and profiles (Configuration),
/// the other IR-controlled devices around it (Equipment), and the live
/// remote (only shown once there's something learned to control). With no
/// IR bridge paired, none of that can send anything, so it explains the
/// bridge instead.
struct AmplifierView: View {
    enum Section: String, CaseIterable, Identifiable {
        case configuration = "Configuration"
        case equipment = "Equipment"
        case remote = "Remote"
        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AmplifierModel()
    @State private var equipmentModel = EquipmentRemoteModel()
    @State private var section: Section = .configuration

    private var remoteAvailable: Bool {
        let ampLearned = model.amplifierTarget?.actions.values.contains { $0.learned } ?? false
        let equipmentHasRemote = equipmentModel.equipment.contains { $0.hasRemote }
        return ampLearned || equipmentHasRemote
    }

    private var visibleSections: [Section] {
        remoteAvailable ? Section.allCases : [.configuration, .equipment]
    }

    var body: some View {
        Group {
            if let snapshot = model.snapshot, !snapshot.irBridgePaired {
                IRBridgeNeededView()
            } else {
                sections
            }
        }
        .navigationTitle("Amplifier")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .task { equipmentModel.configure(settings) }
        .onChange(of: remoteAvailable) { _, available in
            if !available, section == .remote { section = .configuration }
        }
        // Each `Section` case has its own model instance, loaded once via
        // `configure()` — activating a profile in Configuration (a separate
        // AmplifierConfigModel) doesn't touch `model`/`equipmentModel` here,
        // so the Remote segment kept showing whatever was live at first
        // load. Refresh on every segment switch and app-foreground instead
        // of relying on some other screen's action to happen to reload
        // these.
        .onChange(of: section) { _, _ in
            Task { await model.load() }
            Task { await equipmentModel.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.load() }
            Task { await equipmentModel.load() }
        }
    }

    private var sections: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(visibleSections) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            switch section {
            case .configuration:
                AmplifierConfigView(equipmentModel: equipmentModel)
            case .equipment:
                AmplifierEquipmentTab(model: equipmentModel)
            case .remote:
                AmplifierRemoteTab(model: model, equipmentModel: equipmentModel)
            }
        }
    }
}

/// What a new installation shows until its IR bridge is paired. Pairing
/// is done in the web Studio; the bridge is never named by brand (which
/// devices work is listed on the website).
struct IRBridgeNeededView: View {
    var body: some View {
        EmptyStateView(
            icon: "dot.radiowaves.left.and.right",
            title: "An IR bridge is needed",
            message: "Oceano controls your amplifier and the rest of your equipment through an IR bridge: a small Wi-Fi device that sends your remotes' infrared signals. Pair it in the Oceano Studio, under Equipment › IR Bridge. Which bridges work is listed on getoceano.com.\n\nEverything else works without one: recognising what plays, the display and streaming."
        )
    }
}
