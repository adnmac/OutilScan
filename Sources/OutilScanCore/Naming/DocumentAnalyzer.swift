import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct NameSuggestion: Equatable {
    public enum Source: Equatable {
        case appleIntelligence
        case rules
    }

    public var name: DocumentName
    /// Faux si aucune date n'a été trouvée dans le document (la date du jour est alors proposée).
    public var dateFound: Bool
    public var source: Source
}

/// Propose date, émetteur et intitulé à partir du texte reconnu sur les premières pages.
/// Tout reste sur le Mac : OCR Vision et modèle Apple Intelligence local, avec des règles simples en secours.
public enum DocumentAnalyzer {
    /// Le modèle local a une fenêtre de contexte limitée : le haut du document suffit.
    static let maxModelCharacters = 3500

    public static func suggest(pages: [ScanPage], memory: NamingMemory, now: Date = Date()) async -> NameSuggestion {
        let text = await Task.detached(priority: .userInitiated) { recognizedText(of: Array(pages.prefix(2))) }.value
        return await suggest(text: text, memory: memory, now: now, useModel: true)
    }

    static func recognizedText(of pages: [ScanPage]) -> String {
        pages.compactMap { page -> String? in
            guard let image = ImageLoader.cgImage(at: page.imageURL),
                  let lines = try? OCRService.recognizeText(in: image, orientation: page.orientation)
            else { return nil }
            // Ordre de lecture : de haut en bas (Vision place l'origine en bas à gauche), puis de gauche à droite.
            return lines
                .sorted { abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                    ? $0.boundingBox.midY > $1.boundingBox.midY
                    : $0.boundingBox.minX < $1.boundingBox.minX }
                .map(\.text)
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    static func suggest(text: String, memory: NamingMemory, now: Date, useModel: Bool) async -> NameSuggestion {
        var rules = ruleBased(text: text, memory: memory, now: now)
        guard useModel, !text.isEmpty, let reply = await askModel(text: text, memory: memory) else { return rules }

        let fields = parseModelReply(reply)
        var name = rules.name
        if let issuer = fields.issuer, !issuer.isEmpty {
            name.issuer = memory.resolveIssuer(proposed: issuer, text: text)
        }
        if let title = fields.title.map(cleanTitle), !title.isEmpty {
            name.title = title
        }
        // Le modèle peut inventer une date ou prendre celle d'un rendez-vous : on ne la garde que si elle figure
        // dans le texte et n'est pas moins plausible que la meilleure date trouvée par les règles.
        let candidates = DateExtractor.candidates(in: text, now: now)
        let bestScore = candidates.map(\.score).max() ?? 0
        if let date = fields.date,
           let match = candidates.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
           match.score >= max(bestScore, 0) {
            name.date = DocumentName.code(for: match.date)
            rules.dateFound = true
        }
        return NameSuggestion(name: name, dateFound: rules.dateFound, source: .appleIntelligence)
    }

    // MARK: - Règles simples

    /// Types de documents courants, du plus spécifique au plus général.
    static let documentTypes: [(keyword: String, title: String)] = [
        ("note d'honoraires", "NoteHonoraires"), ("avertissement-extrait de role", "AvertissementExtraitRole"),
        ("avis d'imposition", "AvisImposition"), ("fiche de paie", "FichePaie"), ("bulletin de paie", "FichePaie"),
        ("releve de compte", "ReleveCompte"), ("bon de commande", "BonCommande"), ("mise en demeure", "MiseEnDemeure"),
        ("note de credit", "NoteCredit"), ("facture", "Facture"), ("devis", "Devis"), ("attestation", "Attestation"),
        ("contrat", "Contrat"), ("avenant", "Avenant"), ("ordonnance", "Ordonnance"), ("decompte", "Decompte"),
        ("quittance", "Quittance"), ("certificat", "Certificat"), ("rappel", "Rappel"), ("recu", "Recu"),
        ("convocation", "Convocation"), ("courrier", "Courrier"),
    ]

    static func ruleBased(text: String, memory: NamingMemory, now: Date) -> NameSuggestion {
        let date = DateExtractor.bestDate(in: text, now: now)
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let title = documentTypes
            .compactMap { type in folded.range(of: type.keyword).map { (type.title, $0.lowerBound) } }
            .min { $0.1 < $1.1 }?.0 ?? ""
        let issuer = memory.knownIssuer(in: text) ?? firstHeaderLine(of: text).map(DocumentName.issuerCode) ?? ""
        return NameSuggestion(
            name: DocumentName(date: DocumentName.code(for: date ?? now), issuer: issuer, title: title),
            dateFound: date != nil,
            source: .rules
        )
    }

    /// En-tête du document : souvent le nom de l'émetteur, sur l'une des premières lignes.
    static func firstHeaderLine(of text: String) -> String? {
        text.split(separator: "\n").prefix(4).map(String.init).first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.6
                && DateExtractor.candidates(in: line).isEmpty
        }
        .map { $0.split(separator: " ").prefix(3).joined(separator: " ") }
    }

    /// Retire numéros et références : « FACTURE N° 2026-4471 » → `Facture`.
    static func cleanTitle(_ title: String) -> String {
        let words = title.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { word in !word.contains(where: \.isNumber) && !["n°", "no", "nr", "ref"].contains(word.lowercased()) }
            .prefix(3)
            .map { $0.lowercased() }
        return DocumentName.titleCode(words.joined(separator: " "))
    }

    // MARK: - Apple Intelligence

    struct ModelFields {
        var date: Date?
        var issuer: String?
        var title: String?
    }

    static func parseModelReply(_ reply: String) -> ModelFields {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ModelFields() }

        var fields = ModelFields()
        fields.issuer = (json["emetteur"] as? String)?.trimmingCharacters(in: .whitespaces)
        fields.title = (json["intitule"] as? String)?.trimmingCharacters(in: .whitespaces)
        if let raw = json["date"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.isLenient = false
            for format in ["yyyy-MM-dd", "dd/MM/yyyy"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) {
                    fields.date = date.addingTimeInterval(12 * 3600)
                    break
                }
            }
        }
        return fields
    }

    static func prompt(text: String, memory: NamingMemory) -> String {
        var prompt = """
        Voici le texte reconnu sur un document scanné :
        ---
        \(text.prefix(maxModelCharacters))
        ---
        Réponds uniquement avec ce JSON :
        {"date": "AAAA-MM-JJ", "emetteur": "...", "intitule": "..."}
        - date : date d'émission du courrier, souvent en haut sous la forme « Ville, le 12 octobre 2026 ». Jamais la date d'une réunion, d'un rendez-vous, d'une naissance, d'une échéance ni d'une période. Chaîne vide si absente.
        - emetteur : organisme ou entreprise qui a envoyé le document (pas le destinataire), avec son nom propre distinctif, par ex. « CHU Lille », « CC Portes du Luxembourg ». Jamais un terme générique seul comme « Communauté de communes », « Mairie » ou « Ministère ».
        - emetteur : sans forme juridique (SA, SRL, NV, ASBL…).
        - intitule : 2 ou 3 mots, TOUJOURS en français (traduis si le document est en néerlandais ou en anglais) : le type de document suivi de son objet. Exemples : facture d'un hôpital pour des soins → « Facture soins » ; attestation d'une mutuelle → « Attestation mutuelle » ; extrait du registre de population → « Extrait population » ; invitation à une commission → « Invitation commission ». Jamais de numéro ni de nom de personne.
        """
        if !memory.issuers.isEmpty {
            prompt += "\nÉmetteurs déjà connus (réutilise exactement l'un d'eux s'il correspond) : "
                + memory.issuers.prefix(40).joined(separator: ", ")
        }
        if !memory.titles.isEmpty {
            prompt += "\nIntitulés déjà utilisés (inspire-toi de ce style) : " + memory.titles.prefix(20).joined(separator: ", ")
        }
        return prompt
    }

    static func askModel(text: String, memory: NamingMemory) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: """
            Tu analyses des documents administratifs (factures, courriers, attestations) en français, \
            néerlandais ou anglais pour proposer un nom de fichier. Tu réponds uniquement en JSON.
            """)
            var options = GenerationOptions()
            options.temperature = 0
            return try? await session.respond(to: prompt(text: text, memory: memory), options: options).content
        }
        #endif
        return nil
    }
}
