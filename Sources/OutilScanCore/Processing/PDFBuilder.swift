import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PDFBuilderError: LocalizedError {
    case unreadableImage(URL)
    case cannotCreatePDF(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return "Impossible de lire l'image \(url.lastPathComponent)."
        case .cannotCreatePDF(let url): return "Impossible de créer le PDF \(url.path)."
        }
    }
}

/// Assemble les pages numérisées en un PDF multipage, avec une couche de texte OCR invisible.
public enum PDFBuilder {
    /// Qualité JPEG des pages couleur / gris : bon compromis lisibilité / taille.
    static let jpegQuality = 0.75

    public static func build(
        pages: [ScanPage],
        to outputURL: URL,
        ocr: Bool,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        guard let context = CGContext(outputURL as CFURL, mediaBox: nil, [
            kCGPDFContextCreator: "OutilScan",
        ] as CFDictionary) else {
            throw PDFBuilderError.cannotCreatePDF(outputURL)
        }

        for (index, page) in pages.enumerated() {
            guard let original = ImageLoader.cgImage(at: page.imageURL) else {
                context.closePDF()
                throw PDFBuilderError.unreadableImage(page.imageURL)
            }
            let image = compressedForPDF(original)
            let lines = ocr ? ((try? OCRService.recognizeText(in: original, orientation: page.orientation)) ?? []) : []
            draw(image: image, page: page, lines: lines, in: context)
            progress?(index + 1, pages.count)
        }
        context.closePDF()
    }

    private static func draw(image: CGImage, page: ScanPage, lines: [RecognizedLine], in context: CGContext) {
        let pointsPerPixel = 72.0 / Double(max(page.resolution, 1))
        let w = Double(image.width) * pointsPerPixel
        let h = Double(image.height) * pointsPerPixel
        let rotated = page.rotation == 90 || page.rotation == 270
        var mediaBox = CGRect(x: 0, y: 0, width: rotated ? h : w, height: rotated ? w : h)

        context.beginPage(mediaBox: &mediaBox)

        // Rotation appliquée au dessin plutôt qu'aux pixels : l'image d'origine (JPEG ou 1 bit) reste intacte.
        context.saveGState()
        switch page.rotation {
        case 90:
            context.translateBy(x: 0, y: w)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: w, y: h)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: h, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.restoreGState()

        drawInvisibleText(lines, pageSize: mediaBox.size, in: context)
        context.endPage()
    }

    /// Texte invisible superposé aux mots : sélectionnable, recherchable et indexé par Spotlight.
    private static func drawInvisibleText(_ lines: [RecognizedLine], pageSize: CGSize, in context: CGContext) {
        guard !lines.isEmpty else { return }
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in lines {
            let rect = CGRect(
                x: line.boundingBox.minX * pageSize.width,
                y: line.boundingBox.minY * pageSize.height,
                width: line.boundingBox.width * pageSize.width,
                height: line.boundingBox.height * pageSize.height
            )
            guard rect.width > 1, rect.height > 1 else { continue }
            let fontSize = rect.height * 0.85
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let textWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            guard textWidth > 0 else { continue }
            // Étire horizontalement pour que la sélection couvre exactement la ligne imprimée.
            context.textMatrix = CGAffineTransform(scaleX: rect.width / textWidth, y: 1)
            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15)
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
    }

    /// Réencode les pages couleur / gris en JPEG : Quartz embarque alors directement le flux JPEG dans le PDF.
    /// Les pages noir et blanc (1 bit) sont laissées telles quelles, elles sont déjà compactes.
    static func compressedForPDF(_ image: CGImage) -> CGImage {
        guard image.bitsPerComponent > 1 else { return image }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return image }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(data, nil),
              let jpeg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return image }
        return jpeg
    }
}
