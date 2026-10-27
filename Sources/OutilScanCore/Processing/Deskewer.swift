import CoreGraphics
import CoreImage
import Foundation

/// Redresse une page entrée de travers dans le chargeur, pour tous les scanners
/// (le S1300 n'a pas d'option de redressement, et celle du S1500 dépend d'un réglage du pilote).
///
/// Méthode des profils de projection : on cherche l'angle pour lequel les lignes de texte,
/// projetées horizontalement, forment les pics les plus nets.
public enum Deskewer {
    static let analysisWidth = 700
    static let maxAngle = 6.0
    /// En dessous de cet angle, la page est considérée comme droite (évite un ré-échantillonnage inutile).
    static let minimumCorrection = 0.15

    /// Inclinaison en degrés, sens trigonométrique (repère y vers le haut) ; nil si la page n'a pas assez de texte.
    public static func skewAngle(of image: CGImage) -> Double? {
        let scale = min(1, Double(analysisWidth) / Double(image.width))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Points d'encre, hors des bords (ombres, bord de feuille).
        let margin = width / 20
        var xs: [Double] = []
        var ys: [Double] = []
        for row in margin..<(height - margin) {
            for x in margin..<(width - margin) where pixels[row * width + x] < 110 {
                xs.append(Double(x))
                ys.append(Double(height - 1 - row))   // repère y vers le haut
            }
        }
        guard xs.count > 400 else { return nil }

        let diagonal = Int(Double(width + height) * 1.5)
        var bins = [Int](repeating: 0, count: diagonal)
        func sharpness(_ degrees: Double) -> Double {
            let radians = degrees * .pi / 180
            let s = sin(radians), c = cos(radians)
            for i in bins.indices { bins[i] = 0 }
            for i in xs.indices {
                let y = -xs[i] * s + ys[i] * c + Double(width)
                let bin = Int(y)
                if bin >= 0 && bin < diagonal { bins[bin] += 1 }
            }
            return bins.reduce(0.0) { $0 + Double($1 * $1) }
        }

        var best = 0.0
        var bestScore = sharpness(0)
        let straightScore = bestScore
        for degrees in stride(from: -maxAngle, through: maxAngle, by: 0.25) {
            let score = sharpness(degrees)
            if score > bestScore { bestScore = score; best = degrees }
        }
        for degrees in stride(from: best - 0.25, through: best + 0.25, by: 0.025) {
            let score = sharpness(degrees)
            if score > bestScore { bestScore = score; best = degrees }
        }
        // Gain trop faible : pas de lignes nettes (photo, page presque vide) → on ne touche à rien.
        return bestScore > straightScore * 1.02 ? best : 0
    }

    /// Tourne l'image pour annuler l'inclinaison ; les coins découverts sont remplis avec la couleur du papier.
    static func straighten(_ input: CIImage, degrees: Double) -> CIImage {
        guard abs(degrees) >= minimumCorrection else { return input }
        let extent = input.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let rotation = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -degrees * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
        let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        return input.transformed(by: rotation).composited(over: paper).cropped(to: extent)
    }
}
