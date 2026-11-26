import SwiftUI
import UIKit

/// A file the share sheet offers; `id` lets `.sheet(item:)` present it.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for one file. SwiftUI's `ShareLink` needs the file
/// before the tap; a file downloaded on the tap is presented through this.
struct ShareSheet: UIViewControllerRepresentable {
    let file: SharedFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
