import Foundation

/// Langue choisie dans les préférences.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, fr, en, de, it

    public var id: String { rawValue }

    /// Nom de la langue dans sa propre langue (« Deutsch », « Italiano »…), pour qu'on la reconnaisse toujours.
    public var nativeName: String {
        switch self {
        case .system: return L10n.tr("Selon le système")
        case .fr: return "Français"
        case .en: return "English"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        }
    }

    /// Langue effectivement utilisée : pour « système », la première langue préférée de macOS que l'app connaît.
    public var resolved: AppLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            let code = String(identifier.prefix(2))
            if let language = AppLanguage(rawValue: code), language != .system { return language }
        }
        return .en
    }

    public var locale: Locale {
        switch resolved {
        case .fr: return Locale(identifier: "fr_BE")
        case .de: return Locale(identifier: "de_DE")
        case .it: return Locale(identifier: "it_IT")
        default: return Locale(identifier: "en_GB")
        }
    }
}

/// Apparence choisie dans les préférences.
public enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return L10n.tr("Selon le système")
        case .light: return L10n.tr("Clair")
        case .dark: return L10n.tr("Sombre")
        }
    }
}

/// Traductions de l'interface. Le texte français sert de clé : un texte absent de la table s'affiche en français.
/// La table est dans le code (et non dans des fichiers .strings) pour changer de langue sans redémarrer l'app.
public enum L10n {
    nonisolated(unsafe) public static var language: AppLanguage = .system

    public static var locale: Locale { language.locale }

    public static func tr(_ french: String) -> String {
        let target = language.resolved
        guard target != .fr, let entry = table[french] else { return french }
        switch target {
        case .en: return entry.en
        case .de: return entry.de
        case .it: return entry.it
        default: return french
        }
    }

    /// Texte avec valeurs : `tr("Page %d sur %d", 2, 5)`.
    public static func tr(_ french: String, _ arguments: CVarArg...) -> String {
        String(format: tr(french), locale: locale, arguments: arguments)
    }

    /// Singulier / pluriel : `plural(n, one: "1 page", other: "%d pages")`.
    public static func plural(_ count: Int, one: String, other: String) -> String {
        count == 1 ? tr(one) : tr(other, count)
    }

    public static func pages(_ count: Int) -> String {
        plural(count, one: "1 page", other: "%d pages")
    }

    typealias Entry = (en: String, de: String, it: String)

    static let table: [String: Entry] = [
        // Préférences
        "Selon le système": ("System default", "Wie System", "Come il sistema"),
        "Clair": ("Light", "Hell", "Chiaro"),
        "Sombre": ("Dark", "Dunkel", "Scuro"),
        "Apparence": ("Appearance", "Erscheinungsbild", "Aspetto"),
        "Langue": ("Language", "Sprache", "Lingua"),
        "Général": ("General", "Allgemein", "Generale"),
        "Les menus de macOS (Fichier, Édition…) changeront de langue au prochain lancement.":
            ("macOS menus (File, Edit…) will switch language the next time the app starts.",
             "Die macOS-Menüs (Ablage, Bearbeiten …) wechseln beim nächsten Start die Sprache.",
             "I menu di macOS (File, Modifica…) cambieranno lingua al prossimo avvio."),

        // Barre latérale : scanner
        "Scanner": ("Scanner", "Scanner", "Scanner"),
        "Recherche du scanner…": ("Looking for the scanner…", "Scanner wird gesucht …", "Ricerca dello scanner…"),
        "Pilote SANE absent": ("SANE driver missing", "SANE-Treiber fehlt", "Driver SANE mancante"),
        "Installe-le dans le Terminal :": ("Install it in Terminal:", "Installiere ihn im Terminal:", "Installalo nel Terminale:"),
        "Scanner non détecté": ("Scanner not detected", "Kein Scanner gefunden", "Scanner non rilevato"),
        "Branche le scanner en USB et ouvre son capot pour l'allumer.":
            ("Connect the scanner via USB and open its cover to turn it on.",
             "Schließe den Scanner per USB an und öffne die Abdeckung, um ihn einzuschalten.",
             "Collega lo scanner via USB e apri il coperchio per accenderlo."),
        "Firmware manquant": ("Firmware missing", "Firmware fehlt", "Firmware mancante"),
        "Le %@ est branché, mais SANE a besoin du fichier « %@ » fourni par Fujitsu avec ScanSnap Manager.":
            ("The %@ is connected, but SANE needs the file “%@” supplied by Fujitsu with ScanSnap Manager.",
             "Der %@ ist angeschlossen, aber SANE benötigt die Datei „%@“, die Fujitsu mit ScanSnap Manager liefert.",
             "Lo %@ è collegato, ma SANE richiede il file «%@» fornito da Fujitsu con ScanSnap Manager."),
        "Importer le firmware…": ("Import firmware…", "Firmware importieren …", "Importa firmware…"),
        "Choisis le fichier %@ (copié depuis une installation de ScanSnap Manager).":
            ("Choose the file %@ (copied from a ScanSnap Manager installation).",
             "Wähle die Datei %@ (aus einer ScanSnap-Manager-Installation kopiert).",
             "Scegli il file %@ (copiato da un'installazione di ScanSnap Manager)."),
        "Installer": ("Install", "Installieren", "Installa"),
        "Actualiser": ("Refresh", "Aktualisieren", "Aggiorna"),

        // Barre latérale : numérisation
        "Numérisation": ("Scanning", "Scannen", "Scansione"),
        "Face": ("Sides", "Seiten", "Lati"),
        "Recto": ("Single-sided", "Einseitig", "Fronte"),
        "Recto verso": ("Double-sided", "Beidseitig", "Fronte-retro"),
        "Couleur": ("Colour", "Farbe", "Colore"),
        "Niveaux de gris": ("Greyscale", "Graustufen", "Scala di grigi"),
        "Noir et blanc": ("Black & white", "Schwarzweiß", "Bianco e nero"),
        "Résolution": ("Resolution", "Auflösung", "Risoluzione"),
        "Format": ("Paper size", "Papierformat", "Formato"),
        "Redresser les pages": ("Straighten pages", "Seiten begradigen", "Raddrizza le pagine"),
        "Nettoyage": ("Clean-up", "Bereinigung", "Pulizia"),
        "Nettoyer le fond": ("Clean background", "Hintergrund bereinigen", "Pulisci lo sfondo"),
        "Intensité": ("Strength", "Stärke", "Intensità"),
        "Léger": ("Light", "Leicht", "Leggera"),
        "Normal": ("Normal", "Normal", "Normale"),
        "Fort": ("Strong", "Stark", "Forte"),
        "Supprime les ombres du pli et le texte du verso vu par transparence.":
            ("Removes fold shadows and text from the back showing through.",
             "Entfernt Faltschatten und durchscheinenden Text der Rückseite.",
             "Rimuove le ombre delle pieghe e il testo del retro visibile in trasparenza."),
        "Pages blanches": ("Blank pages", "Leere Seiten", "Pagine bianche"),
        "Ignorer les pages blanches": ("Skip blank pages", "Leere Seiten überspringen", "Ignora le pagine bianche"),
        "Sensibilité": ("Sensitivity", "Empfindlichkeit", "Sensibilità"),
        "Faible": ("Low", "Niedrig", "Bassa"),
        "Forte": ("High", "Hoch", "Alta"),
        "Une sensibilité forte ignore aussi les pages presque vides.":
            ("High sensitivity also skips nearly empty pages.",
             "Eine hohe Empfindlichkeit überspringt auch fast leere Seiten.",
             "Una sensibilità alta ignora anche le pagine quasi vuote."),
        "Annuler": ("Cancel", "Abbrechen", "Annulla"),
        "Numériser": ("Scan", "Scannen", "Scansiona"),
        "Numériser et ajouter": ("Scan and add", "Scannen und hinzufügen", "Scansiona e aggiungi"),

        // Dossier d'enregistrement
        "Enregistrement": ("Saving", "Speichern", "Salvataggio"),
        "Choisir": ("Choose", "Auswählen", "Scegli"),
        "Choisir…": ("Choose…", "Auswählen …", "Scegli…"),
        "Ouvrir": ("Open", "Öffnen", "Apri"),
        "Dossier où enregistrer les PDF numérisés": ("Folder where scanned PDFs are saved",
                                                    "Ordner für die gescannten PDFs",
                                                    "Cartella in cui salvare i PDF scansionati"),
        "Ce dossier n'existe plus : choisis-en un autre.": ("This folder no longer exists: choose another one.",
                                                            "Dieser Ordner existiert nicht mehr: Wähle einen anderen.",
                                                            "Questa cartella non esiste più: scegline un'altra."),

        // Fenêtre principale
        "Tout effacer": ("Clear all", "Alles löschen", "Cancella tutto"),
        "Enregistrer le PDF": ("Save PDF", "PDF sichern", "Salva il PDF"),
        "Effacer toutes les pages numérisées ?": ("Delete all scanned pages?", "Alle gescannten Seiten löschen?",
                                                  "Eliminare tutte le pagine scansionate?"),
        "Effacer": ("Delete", "Löschen", "Elimina"),
        "Aucune page": ("No pages", "Keine Seiten", "Nessuna pagina"),
        "Place tes documents dans le chargeur, face imprimée vers le bas, puis clique sur « Numériser ».":
            ("Put your documents in the feeder, printed side down, then click “Scan”.",
             "Lege die Dokumente mit der bedruckten Seite nach unten in den Einzug und klicke auf „Scannen“.",
             "Inserisci i documenti nell'alimentatore, con il lato stampato verso il basso, poi fai clic su «Scansiona»."),
        "1 page": ("1 page", "1 Seite", "1 pagina"),
        "%d pages": ("%d pages", "%d Seiten", "%d pagine"),

        // Grille et aperçu
        "Page %d": ("Page %d", "Seite %d", "Pagina %d"),
        "Page %d sur %d": ("Page %d of %d", "Seite %d von %d", "Pagina %d di %d"),
        "Pivoter à droite": ("Rotate right", "Nach rechts drehen", "Ruota a destra"),
        "Pivoter à gauche": ("Rotate left", "Nach links drehen", "Ruota a sinistra"),
        "Supprimer la page": ("Delete page", "Seite löschen", "Elimina la pagina"),
        "Précédente": ("Previous", "Zurück", "Precedente"),
        "Suivante": ("Next", "Weiter", "Successiva"),
        "Fermer": ("Close", "Schließen", "Chiudi"),

        // Fenêtre d'enregistrement
        "Date": ("Date", "Datum", "Data"),
        "AAMMJJ": ("YYMMDD", "JJMMTT", "AAMMGG"),
        "Choisir la date dans un calendrier": ("Pick the date in a calendar", "Datum im Kalender wählen",
                                               "Scegli la data in un calendario"),
        "Date du document": ("Document date", "Dokumentdatum", "Data del documento"),
        "Aujourd'hui": ("Today", "Heute", "Oggi"),
        "%@ — date du jour, aucune date trouvée": ("%@ — today's date, no date found",
                                                   "%@ – heutiges Datum, kein Datum gefunden",
                                                   "%@ — data di oggi, nessuna data trovata"),
        "Format attendu : AAMMJJ, par ex. 261012": ("Expected format: YYMMDD, e.g. 261012",
                                                    "Erwartetes Format: JJMMTT, z. B. 261012",
                                                    "Formato previsto: AAMMGG, ad es. 261012"),
        "Émetteur": ("Sender", "Absender", "Mittente"),
        "ex. CHU Lille": ("e.g. CHU Lille", "z. B. CHU Lille", "es. CHU Lille"),
        "Intitulé": ("Title", "Titel", "Titolo"),
        "ex. Facture soins": ("e.g. Invoice care", "z. B. Rechnung Behandlung", "es. Fattura cure"),
        "Déjà utilisés": ("Previously used", "Bereits verwendet", "Già usati"),
        "Dossier": ("Folder", "Ordner", "Cartella"),
        "Reconnaissance de texte (OCR)": ("Text recognition (OCR)", "Texterkennung (OCR)", "Riconoscimento del testo (OCR)"),
        "Afficher dans le Finder après l'enregistrement": ("Show in Finder after saving", "Nach dem Sichern im Finder zeigen",
                                                          "Mostra nel Finder dopo il salvataggio"),
        "Enregistrer": ("Save", "Sichern", "Salva"),
        "Lecture du document…": ("Reading the document…", "Dokument wird gelesen …", "Lettura del documento…"),
        "Nom proposé par Apple Intelligence (sur ton Mac)": ("Name suggested by Apple Intelligence (on your Mac)",
                                                             "Name von Apple Intelligence vorgeschlagen (auf deinem Mac)",
                                                             "Nome proposto da Apple Intelligence (sul tuo Mac)"),
        "Nom proposé d'après les mots-clés du document": ("Name suggested from the document's keywords",
                                                          "Name anhand der Schlüsselwörter des Dokuments vorgeschlagen",
                                                          "Nome proposto in base alle parole chiave del documento"),

        // Messages d'état et erreurs
        "Firmware installé pour le %@.": ("Firmware installed for the %@.", "Firmware für den %@ installiert.",
                                          "Firmware installato per lo %@."),
        "Impossible d'installer le firmware : %@": ("Couldn't install the firmware: %@",
                                                    "Firmware konnte nicht installiert werden: %@",
                                                    "Impossibile installare il firmware: %@"),
        "Numérisation…": ("Scanning…", "Scannen …", "Scansione in corso…"),
        "Page %d numérisée…": ("Page %d scanned…", "Seite %d gescannt …", "Pagina %d scansionata…"),
        "Numérisation annulée.": ("Scan cancelled.", "Scan abgebrochen.", "Scansione annullata."),
        "1 page ajoutée": ("1 page added", "1 Seite hinzugefügt", "1 pagina aggiunta"),
        "%d pages ajoutées": ("%d pages added", "%d Seiten hinzugefügt", "%d pagine aggiunte"),
        "1 page blanche ignorée": ("1 blank page skipped", "1 leere Seite übersprungen", "1 pagina bianca ignorata"),
        "%d pages blanches ignorées": ("%d blank pages skipped", "%d leere Seiten übersprungen",
                                       "%d pagine bianche ignorate"),
        "Reconnaissance du texte et création du PDF…": ("Recognising text and creating the PDF…",
                                                        "Text wird erkannt und PDF erstellt …",
                                                        "Riconoscimento del testo e creazione del PDF…"),
        "Création du PDF…": ("Creating the PDF…", "PDF wird erstellt …", "Creazione del PDF…"),
        "Enregistré : %@": ("Saved: %@", "Gesichert: %@", "Salvato: %@"),
        "Le pilote SANE est introuvable. Installe-le avec : brew install sane-backends":
            ("The SANE driver can't be found. Install it with: brew install sane-backends",
             "Der SANE-Treiber wurde nicht gefunden. Installiere ihn mit: brew install sane-backends",
             "Il driver SANE non è stato trovato. Installalo con: brew install sane-backends"),
        "Le chargeur est vide. Place les documents face imprimée vers le bas et réessaie.":
            ("The feeder is empty. Put the documents in printed side down and try again.",
             "Der Einzug ist leer. Lege die Dokumente mit der bedruckten Seite nach unten ein und versuche es erneut.",
             "L'alimentatore è vuoto. Inserisci i documenti con il lato stampato verso il basso e riprova."),
        "Le capot du scanner est ouvert ou le scanner est en veille.":
            ("The scanner cover is open or the scanner is asleep.",
             "Die Scannerabdeckung ist offen oder der Scanner ist im Ruhezustand.",
             "Il coperchio dello scanner è aperto o lo scanner è in standby."),
        "Bourrage papier : retire les feuilles coincées puis relance.":
            ("Paper jam: remove the stuck sheets, then start again.",
             "Papierstau: Entferne die eingeklemmten Blätter und starte erneut.",
             "Inceppamento della carta: rimuovi i fogli bloccati e riprova."),
        "Le scanner est occupé. Quitte ScanSnap Home ou VueScan, puis réessaie.":
            ("The scanner is busy. Quit ScanSnap Home or VueScan, then try again.",
             "Der Scanner ist belegt. Beende ScanSnap Home oder VueScan und versuche es erneut.",
             "Lo scanner è occupato. Chiudi ScanSnap Home o VueScan, poi riprova."),
        "Erreur inconnue": ("Unknown error", "Unbekannter Fehler", "Errore sconosciuto"),
        "Erreur du scanner : %@": ("Scanner error: %@", "Scannerfehler: %@", "Errore dello scanner: %@"),
        "Impossible de lire l'image %@.": ("Couldn't read the image %@.", "Bild %@ konnte nicht gelesen werden.",
                                           "Impossibile leggere l'immagine %@."),
        "Impossible de créer le PDF %@.": ("Couldn't create the PDF %@.", "PDF %@ konnte nicht erstellt werden.",
                                           "Impossibile creare il PDF %@."),
    ]
}
