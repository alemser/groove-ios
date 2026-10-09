import SwiftUI

/// Arranges the remote: drag to reorder within a panel, swipe to hide,
/// pick a width, move a button to another panel, restore hidden ones,
/// reorder/rename/add panels. Every change is saved straight away and
/// applies to the web remote too. Nothing here sends IR.
struct ArrangeRemoteView: View {
    let model: RemoteLayoutModel
    let equipmentModel: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var renamingPanel: String?
    @State private var panelName = ""
    @State private var showNewPanel = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Group {
                if let layout = model.layout {
                    List {
                        ForEach(layout.panels) { panel in
                            panelSection(panel, in: layout)
                        }
                        if !layout.hidden.isEmpty {
                            Section {
                                ForEach(layout.hidden) { c in
                                    Button {
                                        Task { await restore(c) }
                                    } label: {
                                        HStack {
                                            Image(systemName: "plus.circle.fill").foregroundStyle(Brand.ok)
                                            controlLabel(c, panel: nil)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Hidden")
                            } footer: {
                                Text("Tap to put a button back on the remote.").foregroundStyle(Brand.muted)
                            }
                        }
                        if let error = model.actionError {
                            Section { Text(error).foregroundStyle(Brand.err) }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    ContentUnavailableView("Can’t arrange the remote", systemImage: "rectangle.3.group",
                                           description: Text("This Oceano needs a newer rig service."))
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Arrange Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            panelName = ""
                            showNewPanel = true
                        } label: {
                            Label("New Panel", systemImage: "plus.rectangle")
                        }
                        if model.layout?.customised == true {
                            Button(role: .destructive) {
                                confirmReset = true
                            } label: {
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("New Panel", isPresented: $showNewPanel) {
                TextField("Name, e.g. Vinyl Session", text: $panelName)
                Button("Add") { Task { await addPanel() } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Panel", isPresented: Binding(get: { renamingPanel != nil }, set: { if !$0 { renamingPanel = nil } })) {
                TextField("Name", text: $panelName)
                Button("Save") { Task { await renamePanel() } }
                Button("Cancel", role: .cancel) { renamingPanel = nil }
            } message: {
                Text("Leave empty to use the equipment's name.")
            }
            .confirmationDialog("Reset the remote to its default layout?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { Task { await model.reset() } }
            }
        }
    }

    // MARK: - Panels

    private func panelSection(_ panel: RigLayoutPanel, in layout: RigRemoteLayout) -> some View {
        let index = layout.panels.firstIndex { $0.id == panel.id } ?? 0
        return Section {
            if panel.controls.isEmpty {
                Text("Empty — move buttons here from another panel.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
            }
            ForEach(panel.controls) { c in
                controlRow(c, panel: panel, layout: layout)
            }
            .onMove { from, to in
                Task { await model.update { $0.panels[index].controls.move(fromOffsets: from, toOffset: to) } }
            }
            .onDelete { offsets in
                Task { await hide(offsets, inPanel: index) }
            }
        } header: {
            HStack {
                Text(panel.label)
                Spacer()
                Menu {
                    Button {
                        panelName = panel.title ?? ""
                        renamingPanel = panel.id
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    if index > 0 {
                        Button {
                            Task { await model.update { $0.panels.swapAt(index, index - 1) } }
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                    }
                    if index < layout.panels.count - 1 {
                        Button {
                            Task { await model.update { $0.panels.swapAt(index, index + 1) } }
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                    }
                    if (panel.target ?? "").isEmpty && panel.controls.isEmpty {
                        Button(role: .destructive) {
                            Task { await model.update { $0.panels.remove(at: index) } }
                        } label: {
                            Label("Delete Panel", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(.horizontal, 6)
                }
            }
        }
    }

    private func controlRow(_ c: RigLayoutControl, panel: RigLayoutPanel, layout: RigRemoteLayout) -> some View {
        HStack {
            controlLabel(c, panel: panel)
            Spacer()
            Menu {
                Picker("Width", selection: Binding(
                    get: { c.span },
                    set: { span in Task { await setSpan(c, span) } }
                )) {
                    Text("Narrow (¼)").tag(1)
                    Text("Half (½)").tag(2)
                    Text("Full width").tag(4)
                }
                let others = layout.panels.filter { $0.id != panel.id }
                if !others.isEmpty {
                    Menu("Move to") {
                        ForEach(others) { dest in
                            Button(dest.label) { Task { await move(c, to: dest.id) } }
                        }
                    }
                }
            } label: {
                Text(c.span == 4 ? "Full" : c.span == 2 ? "½" : "¼")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Brand.cardElevated)
                    .clipShape(Capsule())
            }
        }
    }

    private func controlLabel(_ c: RigLayoutControl, panel: RigLayoutPanel?) -> some View {
        let owner = panel?.target == c.target ? nil : equipmentModel.equipment.first { $0.id == c.target }?.label
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(c.label).foregroundStyle(Brand.text)
                if let owner {
                    Text(owner).font(.caption2).foregroundStyle(Brand.muted)
                }
            }
        } icon: {
            Image(systemName: c.icon ?? "circle.dashed").foregroundStyle(Brand.accent)
        }
    }

    // MARK: - Changes

    private func hide(_ offsets: IndexSet, inPanel index: Int) async {
        await model.update { l in
            let removed = offsets.map { l.panels[index].controls[$0] }
            l.panels[index].controls.remove(atOffsets: offsets)
            l.hidden.append(contentsOf: removed)
        }
    }

    private func restore(_ c: RigLayoutControl) async {
        await model.update { l in
            l.hidden.removeAll { $0.key == c.key }
            let dest = l.panels.firstIndex { $0.target == c.target } ?? 0
            guard l.panels.indices.contains(dest) else { return }
            l.panels[dest].controls.append(c)
        }
    }

    private func setSpan(_ c: RigLayoutControl, _ span: Int) async {
        await model.update { l in
            for p in l.panels.indices {
                if let i = l.panels[p].controls.firstIndex(where: { $0.key == c.key }) {
                    l.panels[p].controls[i].span = span
                }
            }
        }
    }

    private func move(_ c: RigLayoutControl, to panelId: String) async {
        await model.update { l in
            for p in l.panels.indices { l.panels[p].controls.removeAll { $0.key == c.key } }
            if let dest = l.panels.firstIndex(where: { $0.id == panelId }) {
                l.panels[dest].controls.append(c)
            }
        }
    }

    private func addPanel() async {
        let name = panelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await model.update { l in
            var base = ""
            for ch in name.lowercased() {
                if ch.isLetter || ch.isNumber, ch.isASCII { base.append(ch) } else if !base.hasSuffix("_") { base.append("_") }
            }
            base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if base.isEmpty { base = "panel" }
            var id = base
            var n = 2
            while l.panels.contains(where: { $0.id == id }) {
                id = "\(base)_\(n)"
                n += 1
            }
            l.panels.append(RigLayoutPanel(id: id, title: name, label: name, target: nil, controls: []))
        }
    }

    private func renamePanel() async {
        guard let id = renamingPanel else { return }
        renamingPanel = nil
        let name = panelName.trimmingCharacters(in: .whitespaces)
        await model.update { l in
            if let i = l.panels.firstIndex(where: { $0.id == id }) {
                l.panels[i].title = name
                if !name.isEmpty { l.panels[i].label = name }
            }
        }
        if name.isEmpty { await model.load() } // pick up the default label
    }
}
