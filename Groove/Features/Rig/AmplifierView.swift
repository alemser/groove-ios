import SwiftUI

/// Hub for the amplifier: its own attributes and profiles (Configuration),
/// the other IR-controlled devices around it (Equipment), and the live
/// remote (only shown once there's something learned to control).
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
}
