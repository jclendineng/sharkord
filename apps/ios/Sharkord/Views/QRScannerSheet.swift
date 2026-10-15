import AVFoundation
import SwiftUI
import Vision
import VisionKit

// the camera, looking for one qr code and handing over what it says
struct QRScannerSheet: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan a QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: close)
                    }
                }
        }
        // asked here rather than left to the scanner, which on a mac never asks at all
        .task {
            if access == .notDetermined {
                let isGranted = await AVCaptureDevice.requestAccess(for: .video)

                access = isGranted ? .authorized : .denied
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .authorized:
            scanner
                .ignoresSafeArea()
        case .notDetermined:
            ProgressView()
        default:
            ContentUnavailableView {
                Label("Can't use the camera", systemImage: "camera.fill")
            } description: {
                Text("Allow Sharkord to use the camera in Settings, or point the Camera app at the code instead.")
            } actions: {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // visionkit's scanner where it runs, an iphone or an ipad. an ipad app on a mac has no
    // visionkit scanner, so there it is the plain camera with vision reading each frame
    @ViewBuilder
    private var scanner: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            QRScanner(onScan: onScan)
        } else {
            CameraQRScanner(onScan: onScan)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
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

private struct CameraQRScanner: UIViewRepresentable {
    let onScan: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()

        context.coordinator.start(in: view)

        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {}

    static func dismantleUIView(_ view: CameraPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let onScan: (String) -> Void
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "sharkord.qr-scanner")
        // touched only on the queue
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        @MainActor
        func start(in view: CameraPreviewView) {
            guard
                let camera = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(input)
            else {
                return
            }

            let output = AVCaptureVideoDataOutput()

            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)

            session.addInput(input)

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill

            queue.async { [session] in
                session.startRunning()
            }
        }

        func stop() {
            queue.async { [session] in
                session.stopRunning()
            }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard !hasScanned, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            let request = VNDetectBarcodesRequest()

            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)

            try? handler.perform([request])

            guard let value = request.results?.lazy.compactMap(\.payloadStringValue).first else {
                return
            }

            hasScanned = true

            let onScan = onScan

            DispatchQueue.main.async {
                onScan(value)
            }
        }
    }
}

private final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
