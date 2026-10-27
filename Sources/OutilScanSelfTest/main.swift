import AppKit
import PDFKit
@testable import OutilScanCore


// Petit banc d'essai autonome : XCTest et Swift Testing exigent Xcode (plugins de macros),
// alors que ce projet se compile avec les seuls Command Line Tools.

struct CheckFailure: Error { let message: String }
nonisolated(unsafe) var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !condition() { failures.append("\(file):\(line) \(message)") }
}

func require<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure(message: "\(file):\(line) valeur nil") }
    return value
}

final class OutilScanTests {
    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Page A4 à 150 dpi, blanche ou avec quelques lignes de texte.
    private func makePage(text: String?) -> CGImage {
        let width = 1240, height = 1754
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let text {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40)]
            for line in 0..<5 {
                (text as NSString).draw(at: CGPoint(x: 150, y: 1500 - line * 70), withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return context.makeImage()!
    }

    private func writeTIFF(_ image: CGImage, name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    func testBlankPageIsDetected() {
        check(BlankPageDetector.isBlank(makePage(text: nil), threshold: ScanSettings().blankThreshold))
    }

    func testTextPageIsNotBlank() {
        let page = makePage(text: "Facture numéro 2026-001")
        check(!BlankPageDetector.isBlank(page, threshold: ScanSettings().blankThreshold))
    }

    func testPDFHasAllPagesAndSearchableText() throws {
        let urls = [
            writeTIFF(makePage(text: "Bonjour le monde"), name: "p1.tif"),
            writeTIFF(makePage(text: "Deuxième page"), name: "p2.tif"),
        ]
        var pages = urls.map { ScanPage(imageURL: $0, resolution: 150) }
        pages[1].rotateClockwise()
        let output = tempDir.appendingPathComponent("test.pdf")

        try PDFBuilder.build(pages: pages, to: output, ocr: true)

        let document = try require(PDFDocument(url: output))
        check(document.pageCount == 2)
        // A4 à 150 dpi → environ 595 × 842 points ; la page pivotée est en paysage.
        let first = try require(document.page(at: 0)).bounds(for: .mediaBox)
        check(abs(first.width - 595.2) < 1)
        let second = try require(document.page(at: 1)).bounds(for: .mediaBox)
        check(second.width > second.height)
        check(document.string?.contains("Bonjour") ?? false, "Texte OCR introuvable : \(document.string ?? "nil")")
    }

    /// Le texte est en haut à gauche de l'original : après 90° horaire il doit se trouver en haut à droite.
    func testRotationDirection() throws {
        var page = ScanPage(imageURL: writeTIFF(makePage(text: "Rotation"), name: "r.tif"), resolution: 150)
        page.rotateClockwise()
        let output = tempDir.appendingPathComponent("rotation.pdf")
        try PDFBuilder.build(pages: [page], to: output, ocr: false)
        let pdfPage = try require(PDFDocument(url: output)?.page(at: 0))
        let image = try require(pdfPage.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
            .cgImage(forProposedRect: nil, context: nil, hints: nil))

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Mémoire du contexte : la première ligne correspond au haut de l'image.
        var quadrants = [0, 0, 0, 0] // haut-gauche, haut-droite, bas-gauche, bas-droite
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                quadrants[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)] += 1
            }
        }
        check(quadrants[1] > quadrants.enumerated().filter { $0.offset != 1 }.map(\.element).max()!,
              "encre par quadrant : \(quadrants)")
    }

    // MARK: - Nommage automatique

    static let sampleInvoice = """
    CHU de Lille
    2 avenue Oscar Lambret 59000 Lille
    Patient : M. Dupont   né le 03/04/1961
    FACTURE N° 2026-4471
    Lille, le 12/10/2026
    Soins externes - consultation de cardiologie
    Montant à régler avant le 12/11/2026 : 42,50 €
    """

    func testDocumentNameFormat() {
        check(DocumentName(date: "261012", issuer: "CHU Lille", title: "Facture soins").fileName == "261012-CHULILLE-Facture-Soins")
        check(DocumentName(date: "261012", issuer: "CHULILLE", title: "FactureSoins").fileName == "261012-CHULILLE-Facture-Soins",
              "les anciens intitulés collés sont redécoupés")
        check(DocumentName.titleCode("Facture-Soins") == "Facture-Soins")
        check(DocumentName.titleCode("résultats ECG") == "Resultats-ECG")
        check(DocumentName.issuerCode("CHU de Lille") == "CHULILLE")
        check(DocumentName.issuerCode("Mutualité Chrétienne") == "MUTUALITECHRETIENNE")
        check(DocumentName.issuerCode("Proximus SA") == "PROXIMUS")
        check(DocumentName.issuerCode("Colruyt Group NV") == "COLRUYTGROUP")
        check(DocumentName.issuerCode("Communauté de Communes des Portes du Luxembourg") == "CCPORTESLUXEMBOURG")
        check(DocumentName.titleCode("Attestation de mutuelle") == "Attestation-Mutuelle")
        check(DocumentName.titleCode("échéancier") == "Echeancier")
        check(DocumentName(date: "261012", issuer: "", title: "Facture").fileName == "261012-Facture")
        check(DocumentName.date(fromCode: "261012") != nil)
        check(DocumentName.date(fromCode: "261332") == nil, "mois 13 refusé")
    }

    func testIssueDateIsChosen() {
        let now = DocumentName.date(fromCode: "261027")!
        let date = DateExtractor.bestDate(in: Self.sampleInvoice, now: now)
        check(date.map(DocumentName.code(for:)) == "261012", "date choisie : \(date.map(DocumentName.code(for:)) ?? "aucune")")
        check(DateExtractor.bestDate(in: "Bruxelles, le 3 février 2026\nObjet : rappel", now: now).map(DocumentName.code(for:)) == "260203")
        check(DateExtractor.bestDate(in: "Aucune date ici", now: now) == nil)

        // Courrier réel : tampon à l'année tronquée par l'OCR, et date de réunion plus loin.
        let invitation = """
        Communauté de Communes
        CARIGNAN, Le 23 OCT. 20
        OBJET : Invitation à la commission Environnement
        communauté de communes, qui se déroulera le :
        Lundi 9 novembre 2026 à partir de 18h30,
        """
        let found = DateExtractor.bestDate(in: invitation, now: now).map(DocumentName.code(for:))
        check(found == "261023", "invitation : \(found ?? "aucune")")

        // Courrier du Forem : tampon « 2 9 SEP. 2026 » mal découpé par l'OCR, et date d'effet future dans le texte.
        let forem = """
        forem
        Charleroi, le 2 9 SEP. 2026
        Objet : Votre situation au sein du Forem
        Cher Collègue,
        j'ai le plaisir de vous informer qu'à partir du 1er janvier 2027, vous rejoindrez le site de Wavre
        """
        let foremDate = DateExtractor.bestDate(in: forem, now: now).map(DocumentName.code(for:))
        check(foremDate == "260929", "Forem : \(foremDate ?? "aucune")")

        // Convocation sans date d'émission : ni la date de naissance ni celle du rendez-vous ne conviennent.
        let appointment = "CHU de Lille\nNé(e) le : 17/09/1995\nLe lundi 23 Novembre 2026 à 09:00"
        check(DateExtractor.bestDate(in: appointment, now: now) == nil, "aucune date d'émission à proposer")

        // Facture d'acompte : date de facture dans un tableau, période « du … au … » et début de contrat dans le texte.
        let invoice = """
        TotalEnergies Power & Gas Belgium
        Votre facture
        Référence client
        1/3
        03/08/2026
        Votre première facture d'acompte Août 2026
        Montant total à payer avant le 25/08/2026
        du 01/08/2026
        au 31/08/2026
        Date d'échéance : 25/08/2026
        Votre contrat a débuté le 7 mars, nous ne vous facturons
        """
        let invoiceDate = DateExtractor.bestDate(in: invoice, now: now).map(DocumentName.code(for:))
        check(invoiceDate == "260803", "facture d'acompte : \(invoiceDate ?? "aucune")")
    }

    func testRuleBasedSuggestion() async {
        let now = DocumentName.date(fromCode: "261027")!
        let suggestion = await DocumentAnalyzer.suggest(text: Self.sampleInvoice, memory: NamingMemory(), now: now, useModel: false)
        check(suggestion.name.fileName == "261012-CHULILLE-Facture", "\(suggestion.name.fileName)")
        check(suggestion.dateFound)

        let noDate = await DocumentAnalyzer.suggest(text: "Proximus\nVotre facture", memory: NamingMemory(), now: now, useModel: false)
        check(!noDate.dateFound && noDate.name.date == "261027", "sans date : date du jour proposée")
    }

    func testNamingMemoryLearnsCorrections() {
        var memory = NamingMemory()
        memory.record(proposed: DocumentName(issuer: "CHU de Lille", title: "Facture"),
                      final: DocumentName(issuer: "CHULILLE", title: "Facture soins"))
        check(memory.issuers == ["CHULILLE"])
        check(memory.titles == ["Facture-Soins"])
        check(memory.resolveIssuer(proposed: "CHU de Lille", text: "") == "CHULILLE", "correction réappliquée")
        check(memory.knownIssuer(in: "Centre : CHU Lille, service cardiologie") == "CHULILLE")
        check(memory.resolveIssuer(proposed: "Hôpital Claude Huriez", text: "CHU Lille - Hôpital Claude Huriez") == "CHULILLE",
              "un émetteur connu présent dans le texte est préféré")
    }

    func testModelReplyParsing() {
        let fields = DocumentAnalyzer.parseModelReply(#"Voici : {"date": "2026-10-12", "emetteur": "CHU de Lille", "intitule": "Facture soins"}"#)
        check(fields.date.map(DocumentName.code(for:)) == "261012")
        check(fields.issuer == "CHU de Lille" && fields.title == "Facture soins")
        check(DocumentAnalyzer.parseModelReply("pas de JSON").issuer == nil)
        check(DocumentAnalyzer.cleanTitle("FACTURE N° 2026-4471") == "Facture")
        check(DocumentAnalyzer.cleanTitle("Facture soins") == "Facture-Soins")
    }

    /// Page grise avec texte gris clair (transparence du verso) et texte noir : seul le noir doit rester.
    func testDocumentCleaner() throws {
        let width = 1240, height = 1754
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))            // papier grisâtre
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.70, alpha: 1))            // texte du verso par transparence
        context.fill(CGRect(x: 100, y: 1200, width: 600, height: 6))
        context.setFillColor(CGColor(gray: 0.05, alpha: 1))            // texte réel
        context.fill(CGRect(x: 100, y: 1000, width: 600, height: 6))
        let cleaned = try require(DocumentCleaner.clean(context.makeImage()!, resolution: 150))

        func gray(atX x: Int, y: Int) -> UInt8 {
            var pixel: UInt8 = 0
            let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            probe.draw(cleaned, in: CGRect(x: -x, y: -y, width: width, height: height))
            return pixel
        }
        check(gray(atX: 600, y: 400) > 245, "papier : \(gray(atX: 600, y: 400))")
        check(gray(atX: 300, y: 1203) > 235, "transparence : \(gray(atX: 300, y: 1203))")
        check(gray(atX: 300, y: 1003) < 40, "texte : \(gray(atX: 300, y: 1003))")
    }

    func testOldSettingsStillDecode() throws {
        let old = #"{"side":"simplex","resolution":150,"colorMode":"Gray","paperSize":"a4","skipBlankPages":false,"blankThreshold":0.002,"deskew":true,"ocr":true}"#
        let settings = try JSONDecoder().decode(ScanSettings.self, from: Data(old.utf8))
        check(settings.resolution == 150 && settings.side == .simplex && !settings.skipBlankPages)
        check(settings.cleanBackground && settings.cleanStrength == .normal)
    }

    /// Chaque traduction existe, n'est pas vide et garde les mêmes valeurs insérées (%d, %@) que le français.
    func testTranslations() {
        func specifiers(_ text: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: "%[d@]")
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        for (french, entry) in L10n.table {
            for (code, text) in [("en", entry.en), ("de", entry.de), ("it", entry.it)] {
                check(!text.isEmpty, "\(code) vide pour « \(french) »")
                check(specifiers(text) == specifiers(french), "\(code) : valeurs différentes pour « \(french) »")
            }
        }
        let saved = L10n.language
        defer { L10n.language = saved }
        L10n.language = .de
        check(L10n.tr("Page %d sur %d", 2, 5) == "Seite 2 von 5")
        check(L10n.pages(1) == "1 Seite" && L10n.pages(3) == "3 Seiten")
        check(ScanSide.duplex.label == "Beidseitig")
        L10n.language = .it
        check(ScannerError.noDocuments.errorDescription?.hasPrefix("L'alimentatore") == true)
        L10n.language = .fr
        check(L10n.tr("Texte absent de la table") == "Texte absent de la table")
        check(L10n.tr("Enregistré : %@", "a.pdf") == "Enregistré : a.pdf")
    }

    func testScanimageArguments() {
        var settings = ScanSettings()
        settings.side = .duplex
        settings.colorMode = .gray
        settings.resolution = 200
        let args = settings.scanimageArguments(supportedOptions: ["page-width", "swdeskew", "l", "t", "x", "y"])
        check(Array(args.prefix(6)) == ["--source", "ADF Duplex", "--mode", "Gray", "--resolution", "200"])
        check(args.contains("--page-width"))
        check(args.contains("-x"))
        check(!args.contains("--swdeskew=yes"), "le redressement est fait par l'app, pas par le pilote")
    }

    func testParseDeviceListAndOptions() {
        let devices = SaneScanner.parseDeviceList("fujitsu:libusb:001:004|FUJITSU|ScanSnap S1500\n")
        check(devices == [ScannerDevice(id: "fujitsu:libusb:001:004", vendor: "FUJITSU", model: "ScanSnap S1500")])

        // S1500 (backend fujitsu) : résolution en intervalle, redressement disponible.
        let s1500 = ScannerCapabilities.parse("""
          Scan Mode:
            --source ADF Front|ADF Back|ADF Duplex [ADF Front]
            --mode Lineart|Halftone|Gray|Color [Lineart]
            --resolution 50..600dpi (in steps of 1) [600]
            --swdeskew[=(yes|no)] [no]
        """)
        check(s1500.options.isSuperset(of: ["source", "mode", "resolution", "swdeskew"]))
        check(s1500.sources == ["ADF Front", "ADF Back", "ADF Duplex"], "\(s1500.sources)")
        check(s1500.resolutions == [150, 200, 300, 600], "\(s1500.resolutions)")
        check(s1500.supportsDeskew)
    }

    /// S1300 (backend epjitsu) : liste de résolutions fixe, pas de redressement logiciel.
    func testS1300Capabilities() {
        // Sortie réelle de « scanimage -A » pour le S1300 (SANE 1.4.0).
        let s1300 = ScannerCapabilities.parse("""
          Scan Mode:
            --source ADF Front|ADF Back|ADF Duplex [ADF Front]
            --mode Lineart|Gray|Color [Lineart]
            --resolution 50..600dpi (in steps of 1) [300]
          Geometry:
            -t 0..289.353mm (in steps of 0.0211639) [0]
            --page-width 2.70898..219.428mm (in steps of 0.0211639) [215.872]
            --page-height 0..450.707mm (in steps of 0.0211639) [292.062]
        """)
        let s1300Args = ScanSettings().scanimageArguments(supportedOptions: s1300.options)
        check(!s1300Args.contains("-x") && !s1300Args.contains("-l"), "\(s1300Args)")
        check(s1300Args.contains("--page-width"))
        check(s1300.resolutions == [150, 200, 300, 600], "\(s1300.resolutions)")
        check(ScannerCapabilities.parse("--resolution 150|225|300|600dpi [300]").resolutions == [150, 225, 300, 600])
        check(s1300.colorModes == [.color, .gray, .lineart])
        check(s1300.sides == [.simplex, .duplex])
        check(!s1300.supportsDeskew)

        var settings = ScanSettings()
        settings.resolution = 200
        let listOnly = ScannerCapabilities(resolutions: [150, 225, 300, 600])
        check(listOnly.adjusted(settings).resolution == 225, "200 dpi devrait devenir 225 dpi")

        let simplexOnly = ScannerCapabilities(sources: ["ADF Front"], modes: ["Gray"], resolutions: [300])
        settings.side = .duplex
        settings.colorMode = .color
        let adjusted = simplexOnly.adjusted(settings)
        check(adjusted.side == .simplex && adjusted.colorMode == .gray && adjusted.resolution == 300)
    }

    func testFirmwareDetection() {
        let config = FirmwareHelper.parseConfig("""
        # Fujitsu S1300
        firmware /opt/homebrew/Cellar/sane-backends/1.4.0_2/share/sane/epjitsu/1300_0C26.nal
        usb 0x04c5 0x11ed
        """)
        check(config[0x11ED]?.lastPathComponent == "1300_0C26.nal", "\(config)")

        let devices = FirmwareHelper.parseIORegistry("""
        +-o Root  <class IORegistryEntry>
          +-o AppleT8122USBXHCI@00000000  <class AppleT8122USBXHCI>
          | +-o ScanSnap S1300@00100000  <class IOUSBHostDevice>
          |   {
          |     "idProduct" = 4589
          |     "USB Product Name" = "ScanSnap S1300"
          |     "idVendor" = 1221
          |   }
        """)
        check(devices.contains(FirmwareHelper.USBDevice(name: "ScanSnap S1300", vendorID: 0x04C5, productID: 0x11ED)), "\(devices)")
    }

    func testBlankSensitivityPercent() {
        var settings = ScanSettings()
        settings.blankSensitivity = 0
        check(abs(settings.blankThreshold - 0.0005) < 1e-9)
        settings.blankSensitivity = 100
        check(abs(settings.blankThreshold - 0.01) < 1e-9)
        for percent in [0.0, 1, 37, 50, 99, 100] {
            settings.blankSensitivity = percent
            check(settings.blankSensitivity == percent, "\(percent) % relu comme \(settings.blankSensitivity) %")
        }
        settings.blankSensitivity = 250
        check(settings.blankSensitivity == 100, "valeur saisie hors limites ramenée à 100 %")
        settings.blankSensitivity = -5
        check(settings.blankSensitivity == 0)
        check(ScanSettings().blankSensitivity == 60, "défaut : \(ScanSettings().blankSensitivity) %")
    }

    func testScannerErrorMapping() {
        check(ScannerError.from(stderr: "scanimage: sane_start: Document feeder out of documents") == .noDocuments)
        check(ScannerError.from(stderr: "scanimage: sane_start: Document feeder jammed") == .jammed)
        check(ScannerError.from(stderr: "scanimage: open of device failed: Device busy") == .busy)
    }

    func testFileNaming() throws {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 18; components.hour = 9; components.minute = 5
        let date = try require(Calendar.current.date(from: components))
        check(FileNaming.defaultName(for: date) == "Scan_2026-10-18_0905")

        let first = FileNaming.uniqueURL(directory: tempDir, baseName: "Facture.pdf")
        check(first.lastPathComponent == "Facture.pdf")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        check(FileNaming.uniqueURL(directory: tempDir, baseName: "Facture").lastPathComponent == "Facture (2).pdf")
    }
}

let tests: [(String, (OutilScanTests) async throws -> Void)] = [
    ("Format AAMMJJ-EMETTEUR-Intitule", { $0.testDocumentNameFormat() }),
    ("Choix de la date d'émission", { $0.testIssueDateIsChosen() }),
    ("Proposition par règles", { await $0.testRuleBasedSuggestion() }),
    ("Mémoire des émetteurs", { $0.testNamingMemoryLearnsCorrections() }),
    ("Réponse du modèle", { $0.testModelReplyParsing() }),
    ("Page blanche détectée", { $0.testBlankPageIsDetected() }),
    ("Page de texte non blanche", { $0.testTextPageIsNotBlank() }),
    ("PDF multipage + OCR", { try $0.testPDFHasAllPagesAndSearchableText() }),
    ("Sens de rotation", { try $0.testRotationDirection() }),
    ("Nettoyage du fond", { try $0.testDocumentCleaner() }),
    ("Anciens réglages conservés", { try $0.testOldSettingsStillDecode() }),
    ("Traductions EN / DE / IT", { $0.testTranslations() }),
    ("Arguments scanimage", { $0.testScanimageArguments() }),
    ("Analyse sortie scanimage", { $0.testParseDeviceListAndOptions() }),
    ("Capacités du S1300", { $0.testS1300Capabilities() }),
    ("Détection du firmware", { $0.testFirmwareDetection() }),
    ("Sensibilité en pourcentage", { $0.testBlankSensitivityPercent() }),
    ("Messages d'erreur", { $0.testScannerErrorMapping() }),
    ("Nommage des fichiers", { try $0.testFileNaming() }),
]

var failedTests = 0
for (name, run) in tests {
    failures = []
    do { try await run(try OutilScanTests()) } catch { failures.append("\(error)") }
    if failures.isEmpty {
        print("✔ \(name)")
    } else {
        failedTests += 1
        print("✘ \(name)")
        failures.forEach { print("    \($0)") }
    }
}
print(failedTests == 0 ? "\nTous les tests (\(tests.count)) réussis." : "\n\(failedTests) test(s) en échec.")
// Analyse d'un PDF existant, comme le ferait la fenêtre d'enregistrement : --analyze <fichier.pdf>
if let index = CommandLine.arguments.firstIndex(of: "--analyze"), index + 1 < CommandLine.arguments.count,
   let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[index + 1])) {
    let text = (0..<min(2, document.pageCount)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    print("ℹ︎ \(text.count) caractères lus sur \(min(2, document.pageCount)) page(s)")
    let result = await DocumentAnalyzer.suggest(text: text, memory: NamingMemory.load(), now: Date(), useModel: true)
    print("ℹ︎ Proposition (\(result.source == .appleIntelligence ? "Apple Intelligence" : "règles")) : \(result.name.fileName)")
    print("ℹ︎ date trouvée dans le document : \(result.dateFound ? "oui" : "non")")
    let ns = text as NSString
    for candidate in DateExtractor.candidates(in: text) {
        let start = max(0, candidate.offset - 25)
        let context = ns.substring(with: NSRange(location: start, length: min(45, ns.length - start)))
        print("ℹ︎   candidate \(DocumentName.code(for: candidate.date)) score \(candidate.score) : …\(context.replacingOccurrences(of: "\n", with: " ⏎ "))…")
    }
    for candidate in DateExtractor.candidates(in: text) {
        let context = (text as NSString).substring(with: NSRange(location: max(0, candidate.offset - 25),
                                                                length: min(45, (text as NSString).length - max(0, candidate.offset - 25))))
        print("ℹ︎   candidate \(DocumentName.code(for: candidate.date)) score \(candidate.score) : …\(context.replacingOccurrences(of: "\n", with: " ⏎ "))…")
    }
}

// Nettoyage d'une page : --clean <entrée.tif> <sortie.png> <dpi> [light|normal|strong]
if let index = CommandLine.arguments.firstIndex(of: "--clean"), index + 3 < CommandLine.arguments.count,
   let image = ImageLoader.cgImage(at: URL(fileURLWithPath: CommandLine.arguments[index + 1])) {
    let strength = DocumentCleaner.Strength(rawValue: CommandLine.arguments.dropFirst(index + 4).first ?? "") ?? .normal
    let start = Date()
    print("ℹ︎ inclinaison mesurée : \(Deskewer.skewAngle(of: image).map { String(format: "%.2f°", $0) } ?? "—")")
    if let cleaned = DocumentCleaner.process(image, resolution: Int(CommandLine.arguments[index + 3]) ?? 300,
                                             deskew: true, clean: true, strength: strength),
       let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[index + 2]) as CFURL,
                                                         "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, cleaned, nil)
        CGImageDestinationFinalize(destination)
        print("ℹ︎ nettoyé en \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
    }
}

// Diagnostic du Mac courant (n'influence pas le résultat des tests).
if CommandLine.arguments.contains("--diagnostic") {
    let live = await DocumentAnalyzer.suggest(text: OutilScanTests.sampleInvoice, memory: NamingMemory(), now: Date(), useModel: true)
    print("ℹ︎ Exemple analysé (\(live.source == .appleIntelligence ? "Apple Intelligence" : "règles")) : \(live.name.fileName)")
    let samples = [
        "proximus\nProximus SA de droit public\nBd du Roi Albert II 27, 1030 Bruxelles\nM. Jean Martin\nRue des Lilas 4, 5000 Namur\nVotre facture du 03/09/2026\nNuméro de facture : 612345678\nPériode : du 01/08/2026 au 31/08/2026\nInternet + TV\nÀ payer avant le 25/09/2026 : 89,99 €",
        "SPF FINANCES\nAdministration générale de la Fiscalité\nAVERTISSEMENT-EXTRAIT DE RÔLE\nImpôt des personnes physiques\nExercice d'imposition 2026 - Revenus 2025\nDate d'envoi : 28/06/2026\nMontant remboursé : 412,33 €",
        "Mutualité Chrétienne\nMC Namur\nAttestation d'affiliation\nNous certifions que Mme Claire Martin, née le 14/02/1975,\nest en ordre d'assurabilité pour l'année 2026.\nNamur, le 5 janvier 2026",
        "Stad Gent\nDienst Burgerzaken\nBotermarkt 1, 9000 Gent\nGent, 14 maart 2026\nBetreft: uittreksel uit het bevolkingsregister\nGeachte heer,",
    ]
    for sample in samples {
        let result = await DocumentAnalyzer.suggest(text: sample, memory: NamingMemory(), now: Date(), useModel: true)
        print("ℹ︎   \(result.name.fileName)")
    }
    for missing in FirmwareHelper.missingFirmware() {
        print("ℹ︎ \(missing.productName) branché, firmware attendu : \(missing.destination.path)")
    }
}

exit(failedTests == 0 ? 0 : 1)
