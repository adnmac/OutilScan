import CoreGraphics
import Foundation
import ImageIO

public enum ImageLoader {
    public static func cgImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func thumbnail(at url: URL, maxPixelSize: Int = 400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Détecte les pages blanches (typiquement les versos vides en recto verso).
public enum BlankPageDetector {
    /// Largeur d'analyse : assez grande pour qu'un trait de texte reste sombre après réduction.
    static let analysisWidth = 800
    /// Marge ignorée sur chaque bord (ombres et bords de feuille).
    static let marginRatio = 0.05
    /// Luminance (0–255) sous laquelle un pixel compte comme encre.
    static let darkLuminance: UInt8 = 160

    /// Proportion de pixels sombres dans la zone utile de la page (0–1).
    public static func darkPixelRatio(of image: CGImage) -> Double {
        let scale = min(1, Double(analysisWidth) / Double(image.width))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))

        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 1 }

        let marginX = Int(Double(width) * marginRatio)
        let marginY = Int(Double(height) * marginRatio)
        var dark = 0
        var total = 0
        for y in marginY..<max(marginY + 1, height - marginY) {
            let row = y * width
            for x in marginX..<max(marginX + 1, width - marginX) {
                total += 1
                if pixels[row + x] < darkLuminance { dark += 1 }
            }
        }
        return total == 0 ? 0 : Double(dark) / Double(total)
    }

    public static func isBlank(_ image: CGImage, threshold: Double) -> Bool {
        darkPixelRatio(of: image) < threshold
    }
}
