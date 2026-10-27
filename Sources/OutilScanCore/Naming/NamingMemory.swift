import Foundation

/// Ce que l'app apprend des noms validés : émetteurs connus, corrections et intitulés habituels.
public struct NamingMemory: Codable, Equatable {
    /// Codes d'émetteurs validés, le plus récent en premier (`CHULILLE`, `MUTUALITECHRETIENNE`…).
    public var issuers: [String] = []
    /// Code proposé par l'analyse → code corrigé par l'utilisateur (`CHUDELILLE` → `CHULILLE`).
    public var issuerCorrections: [String: String] = [:]
    /// Intitulés validés, le plus récent en premier.
    public var titles: [String] = []

    static let maxIssuers = 300
    static let maxTitles = 60

    public init() {}

    /// Retient le nom validé par l'utilisateur, et la correction s'il a modifié l'émetteur proposé.
    public mutating func record(proposed: DocumentName, final: DocumentName) {
        let proposedIssuer = DocumentName.issuerCode(proposed.issuer)
        let finalIssuer = DocumentName.issuerCode(final.issuer)
        if !finalIssuer.isEmpty {
            issuers.removeAll { $0 == finalIssuer }
            issuers.insert(finalIssuer, at: 0)
            issuers = Array(issuers.prefix(Self.maxIssuers))
            if !proposedIssuer.isEmpty, proposedIssuer != finalIssuer {
                issuerCorrections[proposedIssuer] = finalIssuer
            }
        }
        let finalTitle = DocumentName.titleCode(final.title)
        if !finalTitle.isEmpty {
            titles.removeAll { $0 == finalTitle }
            titles.insert(finalTitle, at: 0)
            titles = Array(titles.prefix(Self.maxTitles))
        }
    }

    /// Émetteur déjà connu dont le nom apparaît dans le texte (le plus long l'emporte : `CHULILLE` avant `CHU`).
    public func knownIssuer(in text: String) -> String? {
        let haystack = DocumentName.words(text).joined().uppercased()
        return issuers
            .filter { $0.count >= 3 && haystack.contains($0) }
            .max { $0.count < $1.count }
    }

    /// Applique les corrections apprises et préfère un émetteur connu présent dans le texte.
    public func resolveIssuer(proposed: String, text: String) -> String {
        let code = DocumentName.issuerCode(proposed)
        if let corrected = issuerCorrections[code] { return corrected }
        if issuers.contains(code) { return code }
        return knownIssuer(in: text) ?? code
    }

    // MARK: - Persistance

    private static let defaultsKey = "namingMemory"

    public static func load(from defaults: UserDefaults = .standard) -> NamingMemory {
        guard let data = defaults.data(forKey: defaultsKey),
              let memory = try? JSONDecoder().decode(NamingMemory.self, from: data)
        else { return NamingMemory() }
        return memory
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
