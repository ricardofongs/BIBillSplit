import SwiftUI
import UIKit
import Vision
import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
    var completion: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    // Vision/UIKit delegate callbacks aren't guaranteed to land on any
    // particular thread; the OCR work below deliberately hops to the main
    // queue before calling `completion` — `@unchecked Sendable` reflects
    // that existing, manual synchronization.
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate, @unchecked Sendable {
        var completion: ([String]) -> Void

        init(completion: @escaping ([String]) -> Void) {
            self.completion = completion
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Pages are processed one at a time, in order, on a single background
            // queue — Vision requests aren't safe to share or run concurrently
            // across threads, and processing sequentially keeps the receipt's
            // lines in their original top-to-bottom order (ReceiptParser relies
            // on that order when a price appears on the line after its item).
            // `scan` is only read here, never mutated, so it's safe to send
            // across the queue hop despite not being marked `Sendable`.
            nonisolated(unsafe) let scan = scan
            DispatchQueue.global(qos: .userInitiated).async {
                var recognizedTexts: [String] = []

                for pageIndex in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: pageIndex)
                    guard let cgImage = image.cgImage else { continue }

                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true

                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    do {
                        try handler.perform([request])
                        for observation in request.results ?? [] {
                            if let candidate = observation.topCandidates(1).first {
                                recognizedTexts.append(candidate.string)
                            }
                        }
                    } catch {
                        print("Text recognition failed: \(error)")
                    }
                }

                DispatchQueue.main.async {
                    self.completion(recognizedTexts)
                    controller.dismiss(animated: true)
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            // VNDocumentCameraViewControllerDelegate callbacks are documented
            // to arrive on the main thread, so this synchronous call is safe
            // even though the method itself isn't statically main-actor-isolated.
            MainActor.assumeIsolated { controller.dismiss(animated: true) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Scanner failed: \(error.localizedDescription)")
            MainActor.assumeIsolated { controller.dismiss(animated: true) }
        }
    }
}

