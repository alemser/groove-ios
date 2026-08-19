import SwiftUI

/// One-tap remote access from Home — the same live controls as Rig →
/// Amplifier → Remote, without navigating through Rig first.
struct RemoteQuickAccessSheet: View {
    let model: AmplifierModel
    let equipmentModel: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AmplifierRemoteTab(model: model, equipmentModel: equipmentModel)
                .navigationTitle("Remote")
                .navigationBarTitleDisplayMode(.inline)
                .grooveScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        // `model`/`equipmentModel` are shared with HomeView and only load
        // once (configure()'s guard) — a profile switched elsewhere (the
        // Rig tab's Configuration screen, another client) wouldn't show up
        // here otherwise. A sheet's content view is freshly created each
        // time it's presented, so `.task` reliably re-runs on every open.
        .task {
            await model.load()
            await equipmentModel.load()
        }
    }
}
