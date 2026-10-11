import SwiftUI

/// "Which button?" — the first half of adding a button; the second half is
/// pressing it on the remote (`LearnSessionSheet`). Suggests the buttons
/// this kind of equipment usually has (its template), searches the full
/// button vocabulary, and accepts any name as a custom button. Buttons the
/// equipment's built-in model ships codes for skip the second half: picking
/// one just adds it.
struct AddButtonSheet: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel
    /// Called with what to teach; the caller presents the learn sheet.
    let onPick: ([LearnStep]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var have: Set<String> { Set(item.actions ?? []) }
    private var hasPower: Bool { have.contains { EquipmentRemoteModel.powerKeys.contains($0) } }

    /// Vocabulary buttons this equipment doesn't have. The amplifier's input
    /// buttons aren't offered here — they come from its profile's inputs.
    private var available: [RigActionDef] {
        let have = self.have
        let skipPower = hasPower
        let skipInput = item.id == "amplifier"
        return model.vocabulary.filter { (def: RigActionDef) -> Bool in
            if have.contains(def.id) { return false }
            if skipPower && def.group == "power" { return false }
            if skipInput && def.group == "input" { return false }
            return true
        }
    }

    private var matches: [RigActionDef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let underscored = q.replacingOccurrences(of: " ", with: "_")
        return available.filter { $0.label.lowercased().contains(q) || $0.id.contains(underscored) }
    }

    private var customName: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let lower = q.lowercased()
        let taken = model.vocabulary.contains { $0.label.lowercased() == lower }
            || (item.actions ?? []).contains { item.label(for: $0).lowercased() == lower }
        return taken ? nil : q
    }

    /// Built into the model, not on the equipment yet.
    private var shipped: [String] { model.missingShippedButtons(for: item) }

    private var suggested: [String] {
        model.missingTemplateButtons(for: item).filter { !$0.hasPrefix("digit_") }
    }

    private var missingDigits: [String] {
        model.missingTemplateButtons(for: item).filter { $0.hasPrefix("digit_") }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    builtInSection
                    suggestionsSection
                    allButtonsSection
                } else {
                    Section {
                        ForEach(matches) { def in pickRow(def.id, def.label, icon: def.icon) }
                        if let name = customName {
                            Button {
                                pick([LearnStep(action: nil, label: name)])
                            } label: {
                                Label("Add “\(name)” as a custom button", systemImage: "plus.circle")
                            }
                        }
                        if matches.isEmpty && customName == nil {
                            Text("Already on this remote.").foregroundStyle(Brand.muted)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name on the button, e.g. Repeat")
            .navigationTitle("Add Button")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var builtInSection: some View {
        let all = shipped
        if !all.isEmpty, let m = model.builtInModel(for: item) {
            let digits = all.filter { $0.hasPrefix("digit_") }
            Section {
                Button {
                    add(all)
                } label: {
                    Label("Add All \(all.count)", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                ForEach(all.filter { !$0.hasPrefix("digit_") }, id: \.self) { a in
                    pickRow(a, model.vocabularyLabel(a), icon: model.icon(for: a))
                }
                if !digits.isEmpty {
                    Button {
                        add(digits)
                    } label: {
                        Label(digitsLabel(digits), systemImage: "number")
                    }
                }
            } header: {
                Text("Built into the \(m.label)")
            } footer: {
                Text("These already work — tap to put one on the remote, no teaching needed.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let all = model.missingTemplateButtons(for: item)
        if !all.isEmpty {
            Section {
                Button {
                    pick(all.map { LearnStep(action: $0, label: model.vocabularyLabel($0)) })
                } label: {
                    Label("Walk Me Through All \(all.count)", systemImage: "list.number")
                        .font(.body.weight(.semibold))
                }
                ForEach(suggested, id: \.self) { a in
                    pickRow(a, model.vocabularyLabel(a), icon: model.icon(for: a))
                }
                if !missingDigits.isEmpty {
                    Button {
                        pick(missingDigits.map { LearnStep(action: $0, label: model.vocabularyLabel($0)) })
                    } label: {
                        Label(digitsLabel(missingDigits), systemImage: "number")
                    }
                }
            } header: {
                Text("Common on \(model.template(for: item)?.label.lowercased() ?? "these") remotes")
            } footer: {
                Text("Pick one, then press it on the remote — it's added once its code is captured.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    private var allButtonsSection: some View {
        Section("All buttons") {
            ForEach(available.filter { !suggested.contains($0.id) && !shipped.contains($0.id) && $0.group != "numeric" }) { def in
                pickRow(def.id, def.label, icon: def.icon)
            }
        }
    }

    private func pickRow(_ action: String, _ label: String, icon: String?) -> some View {
        Button {
            pick([LearnStep(action: action, label: label)])
        } label: {
            Label {
                Text(label).foregroundStyle(Brand.text)
            } icon: {
                Image(systemName: icon ?? "circle.dashed").foregroundStyle(Brand.accent)
            }
        }
    }

    private func pick(_ steps: [LearnStep]) {
        // One button the model already has a code for (a tap in the
        // built-in section, or a search hit): add it, nothing to learn.
        if steps.count == 1, let a = steps[0].action, shipped.contains(a) {
            add([a])
            return
        }
        onPick(steps)
        dismiss()
    }

    /// "Number Keys 0–9" when all ten are missing, else the ones that are
    /// ("Number Keys 3, 7") — the row only adds/teaches those.
    private func digitsLabel(_ digits: [String]) -> String {
        if digits.count == 10 { return "Number Keys 0–9" }
        let nums = digits.map { String($0.dropFirst("digit_".count)) }.joined(separator: ", ")
        return (digits.count == 1 ? "Number Key " : "Number Keys ") + nums
    }

    private func add(_ actions: [String]) {
        let targetId = item.id
        Task { await model.addShippedButtons(targetId: targetId, actions: actions) }
        dismiss()
    }
}
