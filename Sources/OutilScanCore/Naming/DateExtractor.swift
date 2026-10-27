import Foundation

/// Repère les dates d'un texte OCR et choisit la plus probable comme date d'émission.
public enum DateExtractor {
    public struct Candidate: Equatable {
        public let date: Date
        /// Position dans le texte : les dates du haut de la première page sont favorisées.
        public let offset: Int
        public let score: Int
    }

    static let months: [String: Int] = [
        "janvier": 1, "janv": 1, "fevrier": 2, "fevr": 2, "fev": 2, "mars": 3, "avril": 4, "avr": 4,
        "mai": 5, "juin": 6, "juillet": 7, "juil": 7, "aout": 8, "septembre": 9, "sept": 9,
        "octobre": 10, "oct": 10, "novembre": 11, "nov": 11, "decembre": 12, "dec": 12,
        // Documents belges en néerlandais ou en anglais.
        "januari": 1, "februari": 2, "maart": 3, "april": 4, "mei": 5, "juni": 6, "juli": 7,
        "augustus": 8, "oktober": 10, "december": 12,
        "january": 1, "february": 2, "march": 3, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11,
        // Abréviations des tampons dateurs (« 29 SEP. 2026 »).
        "jan": 1, "feb": 2, "mrt": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "okt": 10,
    ]

    /// Mots qui annoncent la date d'émission…
    static let positiveContext = ["date", "le ", "emis", "facture du", "fait a", "datum", "du "]
    /// … ou au contraire une autre date (naissance, échéance, période).
    static let negativeContext = ["ne le", "nee le", "ne(e) le", "ne(e)", "date de naissance", "naissance", "geboren", "echeance", "avant le", "au plus tard",
                                  "valable", "expire", "periode", "au ", "jusqu",
                                  // Rendez-vous, réunions, convocations : la date de l'événement n'est pas celle du courrier.
                                  "deroulera", "aura lieu", "reunion", "rendez-vous", "seance", "convoque",
                                  "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
                                  // Dates d'effet : « à partir du 1er janvier 2027 ».
                                  "a partir du", "a partir de", "a compter du", "a compter de", "des le", "prendra effet",
                                  "vanaf", "with effect from",
                                  // Début d'un contrat ou d'une situation : « votre contrat a débuté le 7 mars ».
                                  "debute le", "debute", "commence le", "commencera", "depuis le", "depuis"]
    /// « du 01/08/2026 au 31/08/2026 » : une date suivie de « au » ouvre une période.
    static let periodStartPattern = try! NSRegularExpression(pattern: #"^\s*(au|a|jusqu|tot|t/m|-)\s"#)
    /// Les dates situées dans les premières lignes (l'en-tête du courrier) sont favorisées.
    static let headerLineCount = 12
    /// « Carignan, le 23 octobre » : lieu suivi de « le », la formule classique de la date d'un courrier.
    static let letterDatePattern = try! NSRegularExpression(pattern: #"[a-z\-]{3,},\s*le\s*$"#)

    public static func candidates(in text: String, now: Date = Date()) -> [Candidate] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        var found: [Candidate] = []
        let ns = folded as NSString

        let numeric = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})\s?[/.\-]\s?(\d{1,2})\s?[/.\-]\s?(\d{4}|\d{2})(?!\d)"#)
        for match in numeric.matches(in: folded, range: NSRange(location: 0, length: ns.length)) {
            let day = Int(ns.substring(with: match.range(at: 1)))!
            let month = Int(ns.substring(with: match.range(at: 2)))!
            let year = normalizedYear(Int(ns.substring(with: match.range(at: 3)))!)
            if let date = makeDate(day: day, month: month, year: year, now: now) {
                found.append(Candidate(date: date, offset: match.range.location,
                                       score: score(in: ns, range: match.range, date: date, now: now)))
            }
        }

        let monthNames = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        // Mois en toutes lettres ; l'année peut manquer ou être tronquée par l'OCR (« 23 OCT. 20 » sur un tampon).
        // Le jour peut être coupé par l'OCR : « 2 9 SEP. 2026 » pour le 29 septembre.
        let textual = try! NSRegularExpression(pattern: #"(?<!\d)(\d \d|\d{1,2})(?:er)?\s+("# + monthNames + #")\b\.?(?:\s+(\d{2,4}))?"#)
        for match in textual.matches(in: folded, range: NSRange(location: 0, length: ns.length)) {
            let day = Int(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: " ", with: ""))!
            let month = months[ns.substring(with: match.range(at: 2))]!
            let yearText = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
            let year: Int
            if yearText.count == 4 {
                year = Int(yearText)!
            } else if yearText.count == 2, yearText != "20" {
                year = 2000 + Int(yearText)!
            } else {
                year = inferredYear(day: day, month: month, now: now)
            }
            if let date = makeDate(day: day, month: month, year: year, now: now) {
                found.append(Candidate(date: date, offset: match.range.location,
                                       score: score(in: ns, range: match.range, date: date, now: now,
                                                    yearMissing: yearText.count != 4)))
            }
        }
        return found.sorted { $0.offset < $1.offset }
    }

    /// Meilleure date : meilleur contexte, puis la plus haute dans le document.
    /// Une date au contexte négatif (rendez-vous, naissance, date d'effet) n'est jamais retenue :
    /// mieux vaut ne rien proposer que proposer une date fausse.
    public static func bestDate(in text: String, now: Date = Date()) -> Date? {
        candidates(in: text, now: now).filter { $0.score >= 0 }.max { a, b in
            a.score != b.score ? a.score < b.score : a.offset > b.offset
        }?.date
    }

    private static func score(in text: NSString, range: NSRange, date: Date, now: Date, yearMissing: Bool = false) -> Int {
        let location = range.location
        let start = max(0, location - 30)
        let before = text.substring(with: NSRange(location: start, length: location - start))
        let afterStart = range.location + range.length
        let after = text.substring(with: NSRange(location: afterStart, length: min(12, text.length - afterStart)))
        let isLetterDate = letterDatePattern.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil
        var score = 0
        if positiveContext.contains(where: before.hasSuffixWithin) { score += 2 }
        if negativeContext.contains(where: before.hasSuffixWithin) { score -= 4 }
        if isLetterDate { score += 3 }
        if periodStartPattern.firstMatch(in: after, range: NSRange(location: 0, length: (after as NSString).length)) != nil {
            score -= 4
        }
        // Une date d'émission porte presque toujours l'année ; sans elle, c'est souvent une mention dans le texte.
        if yearMissing && !isLetterDate { score -= 1 }
        let lineIndex = text.substring(to: location).filter { $0 == "\n" }.count
        if lineIndex < headerLineCount { score += 1 }
        // Un courrier n'est pas daté de plusieurs semaines dans le futur : c'est une date d'effet ou d'échéance.
        if date > now.addingTimeInterval(14 * 24 * 3600) { score -= 2 }
        return score
    }

    /// Année absente : celle qui place la date le plus près d'aujourd'hui sans la mettre loin dans le futur.
    private static func inferredYear(day: Int, month: Int, now: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: now)
        let thisYear = calendar.date(from: DateComponents(year: currentYear, month: month, day: day)) ?? now
        return thisYear > now.addingTimeInterval(60 * 24 * 3600) ? currentYear - 1 : currentYear
    }

    private static func normalizedYear(_ year: Int) -> Int {
        year < 100 ? 2000 + year : year
    }

    /// Rejette les dates impossibles ou invraisemblables pour un document récent.
    private static func makeDate(day: Int, month: Int, year: Int, now: Date) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month), (1990...2100).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              date < now.addingTimeInterval(400 * 24 * 3600)
        else { return nil }
        return date
    }
}

private extension String {
    /// Vrai si `keyword` figure dans les derniers caractères (le contexte juste avant la date).
    func hasSuffixWithin(_ keyword: String) -> Bool {
        guard let range = range(of: keyword, options: .backwards) else { return false }
        return distance(from: range.upperBound, to: endIndex) <= 14
    }
}
