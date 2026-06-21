import UIKit
import Vision

enum OCR {
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { request, _ in
                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: "")
                    return
                }
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                cont.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(returning: "")
            }
        }
    }
}
