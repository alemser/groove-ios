import SwiftUI

/// Physical hardware: stylus tracking, the amplifier and remote, and stack
/// health. Catalog server connection and recognition/enrichment config live
/// in Settings, not here.
struct RigView: View {
    @Environment(AppSettings.self) private var settings

    @State private var stylusStatusText: String?
    @State private var ampStatusText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Hardware") {
                    NavigationLink {
                        StylusView()
                    } label: {
                        hardwareRow(
                            title: "Stylus Tracking",
                            subtitle: stylusStatusText ?? "Loading…",
                            icon: "gauge.with.dots.needle.33percent",
                            tint: Brand.gold
                        )
                    }
                    NavigationLink {
                        AmplifierView()
                    } label: {
                        hardwareRow(
                            title: "Amplifier",
                            subtitle: ampStatusText ?? "Loading…",
                            icon: "hifispeaker.and.homepod",
                            tint: Brand.teal
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Rig")
        }
        .task { await loadStylusStatus() }
        .task { await loadAmpStatus() }
    }

    private func hardwareRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Brand.text)
                Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
            }
        }
    }

    private func loadStylusStatus() async {
        guard settings.isConfigured else { return }
        do {
            let state = try await CatalogService(settings: settings).stylusState()
            guard let p = state.profile else {
                stylusStatusText = "Not configured"
                return
            }
            stylusStatusText = "\(p.brand) \(p.model) · \(String(format: "%.0f%% worn", state.metrics.wearPercent))"
        } catch {
            stylusStatusText = "Unavailable"
        }
    }

    private func loadAmpStatus() async {
        guard settings.isConfigured else { return }
        do {
            let snapshot = try await CatalogService(settings: settings).rigStatus()
            guard let amp = snapshot.amplifier else {
                ampStatusText = "Not configured"
                return
            }
            let device = [amp.maker, amp.model].compactMap { $0.nonEmpty }.joined(separator: " ")
            let power = (amp.power?.state ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized
            ampStatusText = device.isEmpty ? power : "\(device) · \(power)"
        } catch {
            ampStatusText = "Unavailable"
        }
    }

}
