import SwiftUI
import UIKit

/// The window the message banner lives in. A `.sheet` is presented above the app's own
/// window, so a banner inside it would be hidden behind any open sheet; this window sits
/// above alerts and lets every touch outside the banner through to what's below.
@MainActor
final class MessageBannerWindow {
    private static var window: UIWindow?

    /// Installs the window once, on the scene the app runs in.
    static func install(_ messages: MessageCenter) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else { return }
        let host = UIHostingController(rootView: MessageBannerHost().environment(messages))
        host.view.backgroundColor = .clear
        let banner = PassthroughWindow(windowScene: scene)
        banner.windowLevel = .alert + 1
        banner.rootViewController = host
        banner.isHidden = false
        window = banner
    }
}

/// Touches that land on no banner fall through to the app below.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

/// Shows the message center's current message as a banner under the status bar.
private struct MessageBannerHost: View {
    @Environment(MessageCenter.self) private var messages

    var body: some View {
        VStack {
            if let message = messages.current {
                MessageBannerView(message: message)
                    .id(message.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .animation(.spring(duration: 0.3), value: messages.current?.id)
    }
}

private struct MessageBannerView: View {
    let message: Message
    @Environment(MessageCenter.self) private var messages

    var body: some View {
        HStack(spacing: 10) {
            // Not colour alone: an error carries the warning sign.
            if message.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.warn)
                    .accessibilityLabel("Error")
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Brand.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry = message.retry {
                Button("Retry") {
                    // Dismissed first: a retry that fails again must be able to say so.
                    messages.dismiss(message)
                    Task { await retry() }
                }
                .font(.subheadline.weight(.semibold))
                .tint(Brand.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Brand.cardElevated, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { messages.dismiss(message) }
        .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
            if drag.translation.height < 0 { messages.dismiss(message) }
        })
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to dismiss")
        .task {
            UIAccessibility.post(notification: .announcement, argument: message.text)
            try? await Task.sleep(for: message.isError ? Self.errorDuration : Self.infoDuration)
            messages.dismiss(message)
        }
    }

    /// Chosen: an error stays long enough to be read and acted on; an acknowledgement
    /// only needs a glance. Android's snackbar durations (Long, Short) are of the same order.
    private static let errorDuration: Duration = .seconds(8)
    private static let infoDuration: Duration = .seconds(4)
}
