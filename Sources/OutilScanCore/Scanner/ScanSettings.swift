import Foundation

/// Recto seul ou recto verso (chargeur automatique du S1500).
public enum ScanSide: String, CaseIterable, Codable, Identifiable {
    case simplex
    case duplex

    public var id: String { rawValue }

    /// Valeur attendue par l'option `--source` du backend SANE `fujitsu`.
    public var saneSource: String {
        switch self {
        case .simplex: return "ADF Front"
        case .duplex: return "ADF Duplex"
        }
    }

    public var label: String {
        switch self {
        case .simplex: return "Recto"
        case .duplex: return "Recto verso"
        }
    }
}

public enum ColorMode: String, CaseIterable, Codable, Identifiable {
    case color = "Color"
    case gray = "Gray"
    case lineart = "Lineart"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .color: return "Couleur"
        case .gray: return "Niveaux de gris"
        case .lineart: return "Noir et blanc"
        }
    }
}

public enum PaperSize: String, CaseIterable, Codable, Identifiable {
    case a4, a5, letter, legal

    public var id: String { rawValue }

    /// Dimensions en millimètres (largeur, hauteur).
    public var millimeters: (width: Double, height: Double) {
        switch self {
        case .a4: return (210, 297)
        case .a5: return (148, 210)
        case .letter: return (215.9, 279.4)
        case .legal: return (215.9, 355.6)
        }
    }

    public var label: String {
        switch self {
        case .a4: return "A4"
        case .a5: return "A5"
        case .letter: return "Letter"
        case .legal: return "Legal"
        }
    }
}

public struct ScanSettings: Codable, Equatable {
    public static let resolutions = [150, 200, 300, 600]

    public var side: ScanSide = .duplex
    public var resolution: Int = 300
    public var colorMode: ColorMode = .color
    public var paperSize: PaperSize = .a4
    public var skipBlankPages: Bool = true
    /// Proportion maximale de pixels sombres pour qu'une page soit jugée blanche.
    public var blankThreshold: Double = 0.003
    public var deskew: Bool = true
    public var ocr: Bool = true
    /// Fond blanchi : ombres de pli et transparence du verso supprimées (sans effet en noir et blanc).
    public var cleanBackground: Bool = true
    public var cleanStrength: DocumentCleaner.Strength = .normal

    public init() {}

    /// Décodage tolérant : un réglage absent (ajouté dans une version plus récente) prend sa valeur par défaut
    /// au lieu de faire perdre tous les réglages enregistrés.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScanSettings()
        side = try c.decodeIfPresent(ScanSide.self, forKey: .side) ?? d.side
        resolution = try c.decodeIfPresent(Int.self, forKey: .resolution) ?? d.resolution
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? d.colorMode
        paperSize = try c.decodeIfPresent(PaperSize.self, forKey: .paperSize) ?? d.paperSize
        skipBlankPages = try c.decodeIfPresent(Bool.self, forKey: .skipBlankPages) ?? d.skipBlankPages
        blankThreshold = try c.decodeIfPresent(Double.self, forKey: .blankThreshold) ?? d.blankThreshold
        deskew = try c.decodeIfPresent(Bool.self, forKey: .deskew) ?? d.deskew
        ocr = try c.decodeIfPresent(Bool.self, forKey: .ocr) ?? d.ocr
        cleanBackground = try c.decodeIfPresent(Bool.self, forKey: .cleanBackground) ?? d.cleanBackground
        cleanStrength = try c.decodeIfPresent(DocumentCleaner.Strength.self, forKey: .cleanStrength) ?? d.cleanStrength
    }

    /// Bornes du seuil de page blanche : 0,05 % à 1 % de pixels sombres.
    static let blankThresholdRange = (min: 0.0005, max: 0.01)

    /// Sensibilité de détection des pages blanches, de 0 à 100 %.
    /// Échelle logarithmique : chaque cran a un effet comparable sur les pages presque vides.
    public var blankSensitivity: Double {
        get {
            let low = log(Self.blankThresholdRange.min), high = log(Self.blankThresholdRange.max)
            let ratio = (log(blankThreshold) - low) / (high - low)
            return (min(max(ratio, 0), 1) * 100).rounded()
        }
        set {
            let ratio = min(max(newValue, 0), 100) / 100
            let low = log(Self.blankThresholdRange.min), high = log(Self.blankThresholdRange.max)
            blankThreshold = exp(low + ratio * (high - low))
        }
    }

    private static let defaultsKey = "scanSettings"

    public static func load(from defaults: UserDefaults = .standard) -> ScanSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data)
        else { return ScanSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Arguments `scanimage` correspondant à ces réglages, limités aux options que le backend expose.
    public func scanimageArguments(supportedOptions: Set<String>) -> [String] {
        var args = [
            "--source", side.saneSource,
            "--mode", colorMode.rawValue,
            "--resolution", String(resolution),
        ]
        let size = paperSize.millimeters
        if supportedOptions.contains("page-width") {
            args += ["--page-width", String(size.width), "--page-height", String(size.height)]
        }
        // Zone de numérisation : le S1500 la demande, le S1300 (epjitsu) n'a que page-width / page-height.
        if supportedOptions.isSuperset(of: ["l", "t", "x", "y"]) {
            args += ["-l", "0", "-t", "0", "-x", String(size.width), "-y", String(size.height)]
        }
        return args
    }
}
