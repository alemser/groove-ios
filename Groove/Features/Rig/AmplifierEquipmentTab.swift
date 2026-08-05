import SwiftUI

/// IR-controlled devices other than the amplifier (CD player, tape deck, …):
/// register equipment and edit them. Live command teaching/firing lives in
/// `EquipmentDetailView`; the Remote tab is where learned commands get fired
/// day-to-day.
struct AmplifierEquipmentTab: View {
    let model: EquipmentRemoteModel
    @State private var showAddSheet = false
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var showDeleteConfirm = false

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
        .confirmationDialog(
            "Remove this equipment?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    for index in offsets {
                        let id = model.otherEquipment[index].id
                        Task { await model.deleteEquipment(id: id) }
                    }
                }
                pendingDeleteOffsets = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteOffsets = nil }
        } message: {
            Text("Its learned remote commands are removed too — you'd have to re-teach them if you add it back.")
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
                    pendingDeleteOffsets = offsets
                    showDeleteConfirm = true
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
