import SwiftUI

struct HealthView: View {
    @Environment(AppSettings.self) private var settings
    @State private var status: CatalogStatus?
    @State private var phase: Phase = .loading
    enum Phase: Equatable { case loading, loaded, error(String) }

    var body: some View {
        content
            .navigationTitle("Stack Health")
            .navigationBarTitleDisplayMode(.inline)
            .grooveScreenBackground()
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading: LoadingView()
        case let .error(message): ErrorStateView(message: message) { Task { await load() } }
        case .loaded:
            ScrollView {
                VStack(spacing: 16) {
                    serviceCard(
                        name: "Catalog",
                        healthy: true,
                        detail: settings.baseURL?.absoluteString ?? "—"
                    )
                    serviceCard(
                        name: "Identity",
                        healthy: (status?.identityStatusError?.nonEmpty == nil),
                        detail: status?.identityStatusError?.nonEmpty ?? (status?.playback.active == true ? "Playing now" : "Connected, idle")
                    )

                    VStack(spacing: 0) {
                        if let v = status?.catalogSchemaVersion { InfoRow(label: "Schema version", value: "\(v)"); Divider().overlay(Brand.border) }
                        if let db = status?.catalogDbPath?.nonEmpty { InfoRow(label: "Database", value: db, mono: true); Divider().overlay(Brand.border) }
                        InfoRow(label: "Enrichers", value: enricherSummary)
                    }
                    .padding(16)
                    .grooveCard()

                    if let chain = status?.enricherChain, !chain.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Enricher chain")
                            FlowChips(items: chain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .grooveCard()
                    }
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await load() }
        }
    }

    private var enricherSummary: String {
        let count = status?.enricherChain?.count ?? 0
        return count == 0 ? "None enabled" : "\(count) active"
    }

    private func serviceCard(name: String, healthy: Bool, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((healthy ? Brand.ok : Brand.err).opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: healthy ? "checkmark" : "exclamationmark")
                    .font(.headline).foregroundStyle(healthy ? Brand.ok : Brand.err)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(Brand.text)
                Text(detail).font(.caption).foregroundStyle(Brand.muted).lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .grooveCard()
    }

    private func load() async {
        do {
            status = try await CatalogService(settings: settings).status()
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Badge(text: item, color: Brand.teal)
            }
        }
    }
}
