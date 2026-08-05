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
    }
}
