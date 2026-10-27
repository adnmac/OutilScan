import Foundation
import ImageIO

public struct ScanPage: Identifiable, Equatable {
    public let id = UUID()
    public let imageURL: URL
    /// Résolution de numérisation, pour donner au PDF la taille réelle du papier.
    public let resolution: Int
    /// Rotation horaire en degrés : 0, 90, 180 ou 270.
    public var rotation: Int = 0

    public init(imageURL: URL, resolution: Int, rotation: Int = 0) {
        self.imageURL = imageURL
        self.resolution = resolution
        self.rotation = rotation
    }

    public mutating func rotateClockwise() { rotation = (rotation + 90) % 360 }
    public mutating func rotateCounterClockwise() { rotation = (rotation + 270) % 360 }

    /// Orientation EXIF équivalente, utilisée par Vision pour lire la page redressée.
    public var orientation: CGImagePropertyOrientation {
        switch rotation {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }
}

public enum FileNaming {
    /// Nom proposé par défaut, par ex. `Scan_2026-10-18_1930`.
    public static func defaultName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "Scan_\(formatter.string(from: date))"
    }

    /// Chemin du PDF sans écraser un fichier existant : ajoute « (2) », « (3) »… si nécessaire.
    public static func uniqueURL(directory: URL, baseName: String, fileManager: FileManager = .default) -> URL {
        let cleaned = sanitized(baseName)
        var candidate = directory.appendingPathComponent(cleaned).appendingPathExtension("pdf")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(cleaned) (\(index))").appendingPathExtension("pdf")
            index += 1
        }
        return candidate
    }

    static func sanitized(_ name: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(".pdf") { base = String(base.dropLast(4)) }
        base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return base.isEmpty ? defaultName() : base
    }
}
