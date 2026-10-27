import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Nettoie une page scannée : fond blanc uniforme, sans ombres de pli ni transparence du verso.
///
/// 1. Estime le fond (papier + ombres) en effaçant le texte par un filtre « maximum », puis en le lissant.
/// 2. Divise la page par ce fond : les variations d'éclairage disparaissent, le papier devient uniforme.
/// 3. Étire les niveaux : les gris clairs (texte du verso vu par transparence) passent au blanc, le texte reste noir.
public enum DocumentCleaner {
    public enum Strength: String, CaseIterable, Codable, Identifiable {
        case light, normal, strong
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .light: return "Léger"
            case .normal: return "Normal"
            case .strong: return "Fort"
            }
        }

        /// Niveau (après aplatissement du fond) au-dessus duquel tout devient blanc.
        var whitePoint: CGFloat {
            switch self {
            case .light: return 0.92
            case .normal: return 0.84
            case .strong: return 0.76
            }
        }
    }

    /// Un fond estimé plus sombre que ce seuil est en réalité du contenu (photo, aplat) : on ne l'éclaircit pas.
    static let darkestBackground: CGFloat = 0.6
    static let blackPoint: CGFloat = 0.08

    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Encre renforcée localement : là où le texte le plus foncé du voisinage reste gris (capteur moins sensible
    /// d'un côté, impression pâle), il est ramené vers le noir. Les zones dont le plus foncé est très clair
    /// (transparence du verso, papier) ne sont pas touchées, pour ne pas faire réapparaître ce qu'on a effacé.
    private static let inkKernel = CIColorKernel(source: """
        kernel vec4 inkNormalize(__sample page, __sample localInk) {
            float ink = dot(localInk.rgb, vec3(0.299, 0.587, 0.114));
            float weight = smoothstep(0.80, 0.62, ink);
            float black = ink * 0.85 * weight;
            vec3 c = clamp((page.rgb - black) / (1.0 - black), 0.0, 1.0);
            return vec4(c, page.a);
        }
        """)

    /// Redresse et/ou nettoie une page. Renvoie nil si l'image ne peut pas être traitée.
    public static func process(_ image: CGImage, resolution: Int, deskew: Bool, clean: Bool,
                               strength: Strength = .normal) -> CGImage? {
        var output = CIImage(cgImage: image)
        let extent = output.extent
        if deskew, let angle = Deskewer.skewAngle(of: image) {
            output = Deskewer.straighten(output, degrees: angle)
        }
        // Les pages noir et blanc (1 bit) sont déjà nettes : seul le redressement s'applique.
        if clean && image.bitsPerComponent > 1 {
            output = cleaned(output, resolution: resolution, strength: strength)
        }
        if image.colorSpace?.model == .monochrome || image.bitsPerComponent == 1 {
            // Une page en niveaux de gris reste en niveaux de gris (fichier trois fois plus léger qu'en couleur).
            return context.createCGImage(output, from: extent, format: .L8,
                                         colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!)
        }
        return context.createCGImage(output, from: extent, format: .RGBA8,
                                     colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    public static func clean(_ image: CGImage, resolution: Int, strength: Strength = .normal) -> CGImage? {
        process(image, resolution: resolution, deskew: false, clean: true, strength: strength)
    }

    static func cleaned(_ input: CIImage, resolution: Int, strength: Strength) -> CIImage {
        let pixelsPerMillimeter = Double(resolution) / 25.4

        // Le filtre maximum doit être plus large qu'un trait de texte gras (~1,5 mm) pour l'effacer.
        let background = input
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: pixelsPerMillimeter * 1.5])
            .applyingGaussianBlur(sigma: pixelsPerMillimeter * 4)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: darkestBackground, y: darkestBackground, z: darkestBackground, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
            .cropped(to: input.extent)

        // CIDivideBlendMode calcule « fond de composition / image » : la page est donc le fond de composition.
        var flattened = background.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: input])

        // Encre la plus foncée du voisinage (~1 cm), lissée pour éviter les transitions visibles.
        if let inkKernel {
            let localInk = flattened
                .clampedToExtent()
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: pixelsPerMillimeter * 5])
                .applyingGaussianBlur(sigma: pixelsPerMillimeter * 6)
                .cropped(to: input.extent)
            flattened = inkKernel.apply(extent: input.extent, arguments: [flattened, localInk]) ?? flattened
        }

        // Niveaux : [noir ; blanc] → [0 ; 1], le reste est écrêté.
        let scale = 1 / (strength.whitePoint - blackPoint)
        let bias = -blackPoint * scale
        let leveled = flattened
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ])
            .applyingFilter("CIColorClamp")

        // Bordure blanchie : l'ombre du bord de la feuille n'est jamais du contenu, et l'encre renforcée la noircirait.
        let border = pixelsPerMillimeter * borderMillimeters
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: input.extent)
        return leveled.cropped(to: input.extent.insetBy(dx: border, dy: border)).composited(over: white)
    }

    static let borderMillimeters = 2.5

    /// Copie du scan brut, gardée à côté de la page traitée (`page-0001-brut.tif`).
    public static func rawCopyURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-brut.tif")
    }

    /// Traite le fichier en place (TIFF) en conservant la résolution enregistrée, après en avoir gardé une copie brute.
    @discardableResult
    public static func processFile(at url: URL, resolution: Int, deskew: Bool, clean: Bool,
                                   strength: Strength = .normal) -> Bool {
        guard deskew || clean,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let processed = process(image, resolution: resolution, deskew: deskew, clean: clean, strength: strength)
        else { return false }
        let raw = rawCopyURL(for: url)
        try? FileManager.default.removeItem(at: raw)
        try? FileManager.default.copyItem(at: url, to: raw)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, processed, CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
        return CGImageDestinationFinalize(destination)
    }
}
