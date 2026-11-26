import SwiftUI

/// Settings → Updates: the board's version, how it installs updates, and what it
/// is doing about them. Absent on a board without the update service. Settings
/// reads the status again each time it opens.
struct UpdatesSection: View {
    @Environment(UpdateCenter.self) private var updates
    @State private var busy = false

    var body: some View {
        if let status = updates.status {
            content(status)
        }
    }

    private func content(_ status: UpdateStatus) -> some View {
        Section {
            InfoRow(label: "Version", value: status.installedLabel)
            UpdatePreferenceOptions(selection: status.preference) { choice in
                guard choice != status.preference else { return }
                run { _ = await updates.setPreference(choice) }
            }
            .disabled(busy)
            VStack(alignment: .leading, spacing: 6) {
                Text(status.statusLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.text)
                if let available = status.available {
                    if available.security {
                        SecurityFixBadge()
                    }
                    if let notes = available.notes.nonEmpty {
                        Text(notes).font(.caption).foregroundStyle(Brand.muted)
                    }
                }
            }
            if status.canApprove {
                action("Update now", systemImage: "arrow.down.circle") { await updates.approve() }
            }
            if status.isWaitingToInstall {
                action("Cancel", systemImage: "xmark.circle", role: .destructive) { await updates.withdrawApproval() }
            }
            action("Check now", systemImage: "arrow.clockwise") { await updates.checkNow() }
                .disabled(status.preference == .unset || status.phase == .checking)
        } header: {
            Text("Updates")
        } footer: {
            Text(Self.lastCheckLine(status.lastCheck)).foregroundStyle(Brand.muted)
        }
    }

    /// The footer under Updates. The updater's own error text is for support: it goes
    /// out in the support log (Settings → Support → Share Logs), never on screen.
    /// Android says the same.
    static func lastCheckLine(_ check: UpdateStatus.UpdateCheck?) -> String {
        guard let check else { return "Last checked: never" }
        let when = "Last checked: \(Format.absolute(check.at))"
        guard check.error.nonEmpty != nil else { return when }
        return "\(when). Couldn't check for updates."
    }

    private func action(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        _ perform: @escaping @MainActor () async -> Void
    ) -> some View {
        Button(role: role) {
            run(perform)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(busy)
    }

    private func run(_ perform: @escaping @MainActor () async -> Void) {
        busy = true
        Task {
            await perform()
            busy = false
        }
    }
}
