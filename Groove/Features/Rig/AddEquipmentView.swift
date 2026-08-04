import SwiftUI

/// Registers a new IR-controlled device. Individual commands are taught
/// afterward, one at a time, from the device's detail screen.
struct AddEquipmentView: View {
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var role: RoleOption = .physicalMedia
    @State private var physicalFormat: FormatOption = .cd
    @State private var selectedActions: Set<String> = ["power_toggle", "play", "pause", "stop", "next", "previous"]
    @State private var isSaving = false

    private static let availableActions = ["power_toggle", "play", "pause", "stop", "next", "previous", "eject"]

    enum RoleOption: String, CaseIterable, Identifiable {
        case physicalMedia = "physical_media"
        case streaming
        case other

        var id: String { rawValue }
        var label: String {
            switch self {
            case .physicalMedia: return "Physical Media"
            case .streaming: return "Streaming"
            case .other: return "Other"
            }
        }
    }

    enum FormatOption: String, CaseIterable, Identifiable {
        case vinyl, cd, tape, mixed
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment") {
                    TextField("Label (e.g. CD Player)", text: $label)
                        .autocorrectionDisabled()
                    Picker("Type", selection: $role) {
                        ForEach(RoleOption.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if role == .physicalMedia {
                        Picker("Format", selection: $physicalFormat) {
                            ForEach(FormatOption.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                Section {
                    ForEach(Self.availableActions, id: \.self) { action in
                        Toggle(
                            action.replacingOccurrences(of: "_", with: " ").capitalized,
                            isOn: Binding(
                                get: { selectedActions.contains(action) },
                                set: { isOn in
                                    if isOn { selectedActions.insert(action) } else { selectedActions.remove(action) }
                                }
                            )
                        )
                        .tint(Brand.accent)
                    }
                } header: {
                    Text("Commands to Teach")
                } footer: {
                    Text("You can teach the IR codes for these afterward, one at a time.")
                        .foregroundStyle(Brand.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let req = RigEquipmentSaveRequest(
            id: nil,
            label: label.trimmingCharacters(in: .whitespaces),
            backend: nil,
            actions: Array(selectedActions),
            role: role.rawValue,
            physicalFormat: role == .physicalMedia ? physicalFormat.rawValue : nil,
            inputIds: nil,
            hasRemote: true
        )
        if await model.addEquipment(req) {
            dismiss()
        }
    }
}
