import SwiftUI

/// IR-controlled devices other than the amplifier (CD player, tape deck, …):
/// register equipment, teach commands from the physical remote, and fire
/// learned commands.
struct EquipmentRemoteView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = EquipmentRemoteModel()
    @State private var showAddSheet = false

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading equipment…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle("Equipment & Remote")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Equipment")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEquipmentView(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.otherEquipment.isEmpty {
            EmptyStateView(
                icon: "appletvremote.gen4",
                title: "No Equipment Yet",
                message: "Add a CD player or other IR-controlled device to teach it remote commands."
            )
        } else {
            List {
                ForEach(model.otherEquipment) { item in
                    NavigationLink {
                        EquipmentDetailView(item: item, model: model)
                    } label: {
                        row(item)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let id = model.otherEquipment[index].id
                        Task { await model.deleteEquipment(id: id) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: RigEquipmentItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: item))
                .foregroundStyle(Brand.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).foregroundStyle(Brand.text)
                Text(subtitle(item)).font(.caption).foregroundStyle(Brand.muted)
            }
        }
    }

    private func icon(for item: RigEquipmentItem) -> String {
        switch item.role {
        case "physical_media": return "opticaldisc"
        case "streaming": return "dot.radiowaves.left.and.right"
        default: return "appletvremote.gen4"
        }
    }

    private func subtitle(_ item: RigEquipmentItem) -> String {
        let roleLabel = item.role.replacingOccurrences(of: "_", with: " ").capitalized
        let actions = item.actions ?? []
        let learned = actions.filter { model.isLearned(targetId: item.id, action: $0) }.count
        return "\(roleLabel) · \(learned)/\(actions.count) commands learned"
    }
}
