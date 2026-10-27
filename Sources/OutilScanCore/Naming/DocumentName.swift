import Foundation

/// Nom de fichier selon la convention de l'utilisateur : `AAMMJJ-EMETTEUR-Intitule`,
/// par ex. `261012-CHULILLE-Facture-Soins` pour une facture de soins du CHU de Lille du 12/10/2026.
public struct DocumentName: Equatable {
    /// Date du document au format `AAMMJJ` (vide si inconnue).
    public var date: String
    /// Émetteur en majuscules sans espaces, par ex. `CHULILLE`.
    public var issuer: String
    /// Intitulé, mots séparés par des tirets, par ex. `Facture-Soins`.
    public var title: String

    public init(date: String = "", issuer: String = "", title: String = "") {
        self.date = date
        self.issuer = issuer
        self.title = title
    }

    /// Nom final ; les parties vides sont omises, tout est normalisé même si l'utilisateur a tapé « CHU Lille ».
    public var fileName: String {
        [
            date.filter(\.isNumber),
            Self.issuerCode(issuer),
            Self.titleCode(title),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    }

    // MARK: - Dates

    private static let posix = Locale(identifier: "en_US_POSIX")

    public static func code(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }

    /// `261012` → 12 octobre 2026 (nil si le code n'est pas une date valide).
    public static func date(fromCode code: String) -> Date? {
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "yyMMdd"
        formatter.isLenient = false
        guard let date = formatter.date(from: code), Self.code(for: date) == code else { return nil }
        return date
    }

    // MARK: - Normalisation

    /// Mots de liaison retirés : « CHU de Lille » → `CHULILLE`, « Attestation de mutuelle » → `AttestationMutuelle`.
    static let stopWords: Set<String> = ["de", "du", "des", "la", "le", "les", "d", "l", "et", "a", "au", "aux", "en", "pour", "sur"]

    static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    /// Formes juridiques retirées de l'émetteur : « Proximus SA » → `PROXIMUS`.
    static let legalForms: Set<String> = ["sa", "srl", "sprl", "scrl", "sc", "asbl", "sas", "sarl", "eurl", "snc",
                                          "nv", "bv", "bvba", "cvba", "vzw", "ltd", "llc", "inc", "gmbh", "ag"]

    public static func issuerCode(_ text: String) -> String {
        // Déjà sous forme de code (« CHULILLE ») : on le garde tel quel.
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        if !folded.isEmpty, folded.allSatisfy({ $0.isUppercase || $0.isNumber }) { return folded }
        var parts = words(abbreviated(text))
        // Forme juridique retirée seulement en fin de nom : « SA Immo » reste `SAIMMO`.
        while parts.count > 1, let last = parts.last, legalForms.contains(last) { parts.removeLast() }
        return parts.joined().uppercased()
    }

    /// Désignations longues remplacées par leur sigle usuel.
    static let abbreviations: [(String, String)] = [
        ("communaute de communes", "CC"), ("communaute d'agglomeration", "CA"),
        ("centre hospitalier universitaire", "CHU"), ("centre hospitalier", "CH"),
        ("centre public d'action sociale", "CPAS"), ("service public federal", "SPF"),
        ("caisse primaire d'assurance maladie", "CPAM"), ("caisse d'allocations familiales", "CAF"),
    ]

    static func abbreviated(_ text: String) -> String {
        var result = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
        for (long, short) in abbreviations {
            result = result.replacingOccurrences(of: long, with: short)
        }
        return result
    }

    /// « facture de soins », « FactureSoins » ou « Facture-Soins » → `Facture-Soins`.
    /// Les mots gardent la casse tapée (`ECG` reste `ECG`), seule leur initiale passe en majuscule.
    public static func titleCode(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        // Découpe aussi les intitulés « collés » des anciens noms : « FactureSoins » → « Facture Soins ».
        let separated = folded.replacingOccurrences(of: #"(?<=[a-z])(?=[A-Z])"#, with: " ", options: .regularExpression)
        return separated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0.lowercased()) }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }
}
