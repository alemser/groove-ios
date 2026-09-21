import SwiftUI
import VisionKit

/// Wraps VisionKit's `DataScannerViewController` for the "Add Release" barcode
/// field — point the phone's camera at a disc's EAN/UPC instead of typing it.
/// Restricted to barcode symbologies only (no text/QR noise from a busy
/// record sleeve or label).
private struct BarcodeCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [
                .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14,
            ])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        // Guards against the delegate firing again with the controller still
        // on screen for the instant it takes the presenter to dismiss it.
        private var delivered = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    delivered = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}

/// Presentable sheet around `BarcodeCameraView` — checks device support and
/// camera permission up front so a Simulator build or a denied permission
/// shows a clear message instead of a blank/frozen camera preview.
struct BarcodeScannerSheet: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeCameraView { payload in
                        let digits = Barcode.digits(from: payload)
                        onScan(digits.isEmpty ? payload : digits)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera scan unavailable",
                        systemImage: "barcode.viewfinder",
                        description: Text(DataScannerViewController.isSupported
                            ? "Camera access is unavailable — check Settings → Privacy → Camera."
                            : "This device doesn't support the camera barcode scanner. Type the barcode instead.")
                    )
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
