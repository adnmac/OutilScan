import Foundation

/// Ce qu'un scanner accepte réellement, lu dans la sortie de `scanimage -A`.
/// Le S1500 (backend `fujitsu`) et le S1300 (backend `epjitsu`) n'ont pas les mêmes résolutions ni les mêmes options.
public struct ScannerCapabilities: Equatable {
    /// Noms des options sans tirets (`source`, `swdeskew`, `page-width`…).
    public var options: Set<String> = []
    /// Valeurs de `--source`, par ex. `ADF Front`, `ADF Duplex`.
    public var sources: [String] = []
    /// Valeurs de `--mode`, par ex. `Lineart`, `Gray`, `Color`.
    public var modes: [String] = []
    /// Résolutions proposées dans l'interface (dpi).
    public var resolutions: [Int] = []

    public init(options: Set<String> = [], sources: [String] = [], modes: [String] = [], resolutions: [Int] = []) {
        self.options = options
        self.sources = sources
        self.modes = modes
        self.resolutions = resolutions
    }

    /// Valeurs par défaut si les options n'ont pas pu être lues : on laisse tout proposer.
    public static let unknown = ScannerCapabilities(
        sources: ScanSide.allCases.map(\.saneSource),
        modes: ColorMode.allCases.map(\.rawValue),
        resolutions: ScanSettings.resolutions
    )

    public var sides: [ScanSide] {
        let available = ScanSide.allCases.filter { sources.contains($0.saneSource) }
        return available.isEmpty ? ScanSide.allCases : available
    }

    public var colorModes: [ColorMode] {
        let available = ColorMode.allCases.filter { modes.contains($0.rawValue) }
        return available.isEmpty ? ColorMode.allCases : available
    }

    public var supportsDeskew: Bool { options.contains("swdeskew") }

    /// Ramène des réglages à ce que le scanner sait faire (par ex. 200 dpi → 225 dpi sur un S1300).
    public func adjusted(_ settings: ScanSettings) -> ScanSettings {
        var result = settings
        if !sides.contains(result.side), let fallback = sides.last { result.side = fallback }
        if !colorModes.contains(result.colorMode), let first = colorModes.first { result.colorMode = first }
        if !resolutions.isEmpty, !resolutions.contains(result.resolution) {
            result.resolution = resolutions.min { abs($0 - settings.resolution) < abs($1 - settings.resolution) }!
        }
        return result
    }

    // MARK: - Analyse de `scanimage -A`

    public static func parse(_ output: String) -> ScannerCapabilities {
        var caps = ScannerCapabilities()
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Options longues (« --mode ») et courtes (« -x », zone de numérisation : absentes sur le S1300).
            guard line.hasPrefix("-") else { continue }
            let dashes = line.hasPrefix("--") ? 2 : 1
            let name = String(line.dropFirst(dashes).prefix { $0.isLetter || $0.isNumber || $0 == "-" })
            guard !name.isEmpty, dashes == 2 || name.count == 1 else { continue }
            caps.options.insert(name)

            // « --mode Lineart|Gray|Color [Lineart] » → « Lineart|Gray|Color »
            var values = String(line.dropFirst(dashes + name.count)).trimmingCharacters(in: .whitespaces)
            if let bracket = values.range(of: " [", options: .backwards) {
                values = String(values[..<bracket.lowerBound])
            }
            switch name {
            case "source": caps.sources = splitList(values)
            case "mode": caps.modes = splitList(values)
            case "resolution": caps.resolutions = parseResolutions(values)
            default: break
            }
        }
        return caps
    }

    private static func splitList(_ values: String) -> [String] {
        values.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Accepte une liste (`150|225|300|600dpi`) ou un intervalle (`50..600dpi (in steps of 1)`).
    static func parseResolutions(_ values: String) -> [Int] {
        let cleaned = values.replacingOccurrences(of: "dpi", with: "")
        if let range = cleaned.range(of: "..") {
            let low = Int(cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespaces)) ?? 0
            let highText = cleaned[range.upperBound...].prefix { $0.isNumber }
            let high = Int(highText) ?? Int.max
            return ScanSettings.resolutions.filter { $0 >= low && $0 <= high }
        }
        return splitList(cleaned).compactMap { Int($0) }.filter { $0 >= 75 }
    }
}
