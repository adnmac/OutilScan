import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct RecognizedLine: Equatable {
    public let text: String
    /// Rectangle normalisé (0–1), origine en bas à gauche, dans l'image redressée.
    public let boundingBox: CGRect
}

/// Reconnaissance de texte locale (framework Vision d'Apple, hors ligne).
public enum OCRService {
    public static let languages = ["fr-FR", "nl-NL", "en-US", "de-DE"]

    public static func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
}
