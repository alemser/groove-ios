import SwiftUI

/// Which audio-recognition providers (ACRCloud, AudD, the local fingerprint
/// index, …) are enabled and in what order — proxied through `groove-catalog`
/// to `groove-identity`'s `/recognition/providers`. Distinct from Rig's
/// "Metadata Enrichers": this is what identifies a spinning record, not what
/// fills in a confirmed track's metadata.
struct RecognitionProvidersScreen: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = RecognitionProvidersModel()
    @State private var credentialsTarget: CredentialsTarget?
    @State private var customProviderTarget: CustomProviderTarget?
    @State private var chainMode = "first_success"
    @State private var minConfidence = 0.6

    private struct CredentialsTarget: Identifiable {
        let id: String
    }

    private struct CustomProviderTarget: Identifiable {
        let id: String
        let existing: CustomProviderConfig?
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading providers…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle("Recognition Providers")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    customProviderTarget = CustomProviderTarget(id: "new", existing: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Custom Provider")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .onChange(of: model.state?.chainMode) { _, new in if let new { chainMode = new } }
        .onChange(of: model.state?.minConfidence) { _, new in if let new { minConfidence = new } }
        .sheet(item: $credentialsTarget) { target in
            ProviderCredentialsView(providerID: target.id, model: model)
        }
        .sheet(item: $customProviderTarget) { target in
            CustomProviderFormView(existing: target.existing, model: model)
        }
    }

    private var isAutonomous: Bool { model.state?.autonomous ?? false }

    private var content: some View {
        List {
            Section {
                Toggle(
                    "Autonomous Mode",
                    isOn: Binding(
                        get: { isAutonomous },
                        set: { newValue in Task { await model.setAutonomous(newValue) } }
                    )
                )
                .tint(Brand.accent)
            } footer: {
                Text("Never contact ACRCloud, AudD, or any custom provider — only the local fingerprint index runs. A track it doesn't recognize shows up in Library → Needs Association for you to pick a release; once picked, Groove learns it and recognizes it offline from then on.")
                    .foregroundStyle(Brand.muted)
            }

            Section {
                Picker("Chain Mode", selection: $chainMode) {
                    Text("First Success").tag("first_success")
                    Text("Best Score").tag("best_score")
                }
                .disabled(isAutonomous)
                .onChange(of: chainMode) { _, new in Task { await model.saveChainSettings(chainMode: new, minConfidence: minConfidence) } }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum Confidence: \(String(format: "%.0f%%", minConfidence * 100))")
                        .foregroundStyle(Brand.text)
                    Slider(value: $minConfidence, in: 0...1, step: 0.05) { editing in
                        if !editing { Task { await model.saveChainSettings(chainMode: chainMode, minConfidence: minConfidence) } }
                    }
                    .tint(Brand.accent)
                    .disabled(isAutonomous)
                }
            } header: {
                Text("Chain Settings")
            } footer: {
                if isAutonomous {
                    Text("Inactive while Autonomous Mode is on.").foregroundStyle(Brand.muted)
                }
            }

            Section {
                ForEach(model.state?.chain ?? []) { slot in
                    row(slot)
                }
                .onMove { indices, newOffset in
                    guard var ids = model.state?.chain.map(\.id) else { return }
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await model.reorder(ids) }
                }
            } header: {
                Text("Chain Order")
            } footer: {
                Text(isAutonomous
                     ? "Inactive while Autonomous Mode is on — providers here are never contacted."
                     : "Tried top to bottom until one identifies the track. Drag to reorder; tap a provider to edit its credentials.")
                    .foregroundStyle(Brand.muted)
            }

            Section {
                if let customs = model.state?.customProviders, !customs.isEmpty {
                    ForEach(customs) { cp in
                        Button {
                            customProviderTarget = CustomProviderTarget(id: cp.id, existing: cp)
                        } label: {
                            customProviderRow(cp)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        guard let customs = model.state?.customProviders else { return }
                        for index in offsets {
                            Task { await model.deleteCustomProvider(slug: customs[index].id) }
                        }
                    }
                } else {
                    Text("No custom providers yet.").font(.footnote).foregroundStyle(Brand.muted)
                }
            } header: {
                Text("Custom Providers")
            } footer: {
                Text("Any HTTP recognition service that returns JSON — tap + to add one.")
                    .foregroundStyle(Brand.muted)
            }

            if let usage = model.usage {
                usageSection(usage)
            }

            if let error = model.actionError {
                Section {
                    Text(error).foregroundStyle(Brand.err)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// "Local index & warm map" usage panel — the same telemetry as the web
    /// providers page's collapsible KPI section, sourced from
    /// `GET /identity/observability/providers`.
    private func usageSection(_ usage: ProviderUsageRollup) -> some View {
        Section {
            InfoRow(label: "Index probes", value: "\(usage.local.index.hits + usage.local.index.misses + usage.local.index.errors)")
            InfoRow(label: "Index hits", value: "\(usage.local.index.hits)")
            InfoRow(label: "Hit rate", value: String(format: "%.0f%%", usage.local.index.hitRate * 100))
            InfoRow(label: "Hit rate (fingerprinted)", value: String(format: "%.0f%%", usage.local.index.hitRateWhenFingerprint * 100))
            InfoRow(label: "Captures won locally", value: "\(usage.local.index.capturesWonByLocal)")
            InfoRow(label: "Fingerprinted captures", value: "\(usage.local.index.fingerprintedCaptures)")

            ForEach(usage.providers) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.provider.capitalized).foregroundStyle(Brand.text)
                    Text("\(row.calls) calls · \(row.matched) matched · \(row.used) used · \(row.errors) errors · avg \(row.avgLatencyMs)ms")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
        } header: {
            Text("Local Index & Providers Usage")
        } footer: {
            Text("Last \(usage.periodDays) days.").foregroundStyle(Brand.muted)
        }
    }

    private func customProviderRow(_ cp: CustomProviderConfig) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cp.displayName.nonEmpty ?? cp.id).foregroundStyle(Brand.text)
                Text(cp.endpointUrl).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
        }
    }

    private func row(_ slot: ProviderSlot) -> some View {
        HStack(spacing: 12) {
            if hasCredentialsForm(slot.id) {
                Button {
                    credentialsTarget = CredentialsTarget(id: slot.id)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.displayName?.nonEmpty ?? slot.id.capitalized)
                                .foregroundStyle(Brand.text)
                            Text(subtitle(slot))
                                .font(.caption)
                                .foregroundStyle(subtitleColor(slot))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(slot.displayName ?? slot.id) credentials")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayName?.nonEmpty ?? slot.id.capitalized)
                        .foregroundStyle(Brand.text)
                    Text(subtitle(slot))
                        .font(.caption)
                        .foregroundStyle(subtitleColor(slot))
                }
                Spacer()
            }
            Toggle(
                "",
                isOn: Binding(
                    get: { slot.enabled },
                    set: { newValue in Task { await model.setEnabled(id: slot.id, enabled: newValue) } }
                )
            )
            .labelsHidden()
            .tint(Brand.accent)
        }
    }

    private func hasCredentialsForm(_ id: String) -> Bool {
        model.state?.builtins[id] != nil
    }

    private func subtitle(_ slot: ProviderSlot) -> String {
        guard hasCredentialsForm(slot.id) else { return "Local — no credentials needed" }
        return slot.configured ? "Configured" : "Needs credentials"
    }

    private func subtitleColor(_ slot: ProviderSlot) -> Color {
        guard hasCredentialsForm(slot.id) else { return Brand.muted }
        return slot.configured ? Brand.ok : Brand.warn
    }
}
