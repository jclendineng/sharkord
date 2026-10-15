import SwiftUI
import VisionKit

// the camera, looking for one qr code and handing over what it says
struct QRScannerSheet: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner(onScan: onScan)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Can't use the camera",
                        systemImage: "camera.fill",
                        description: Text("Allow Sharkord to use the camera in Settings, or point the Camera app at the code instead.")
                    )
                }
            }
            .navigationTitle("Scan a QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
    }

    private func close() {
        dismiss()
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator
        try? scanner.startScanning()

        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else {
                return
            }

            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    hasScanned = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
