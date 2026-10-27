import Foundation

/// État de l'application : scanner détecté, pages numérisées, numérisation et enregistrement en cours.
@MainActor
public final class ScanSession: ObservableObject {
    public enum ScannerState: Equatable {
        case searching
        case driverMissing
        case notFound
        /// Scanner branché mais inutilisable tant que son firmware n'est pas installé (S300, S1300, S1100…).
        case firmwareMissing(MissingFirmware)
        case ready(ScannerDevice)
    }

    @Published public var settings: ScanSettings {
        didSet { settings.save() }
    }
    @Published public private(set) var scannerState: ScannerState = .searching
    /// Tous les scanners SANE détectés (par ex. un S1500 et un S1300 branchés en même temps).
    @Published public private(set) var devices: [ScannerDevice] = []
    @Published public private(set) var capabilities: ScannerCapabilities = .unknown
    @Published public var pages: [ScanPage] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var scannedInCurrentBatch = 0
    @Published public private(set) var skippedInCurrentBatch = 0
    @Published public private(set) var isSaving = false
    @Published public private(set) var saveProgress: Double = 0
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?

    private let scanner = SaneScanner()
    private var capabilitiesByDevice: [String: ScannerCapabilities] = [:]
    private static let selectedDeviceKey = "selectedScanner"
    private let workDirectory: URL

    public init() {
        settings = ScanSettings.load()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutilScan-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    public var device: ScannerDevice? {
        if case .ready(let device) = scannerState { return device }
        return nil
    }

    // MARK: - Détection

    public func detectScanner() async {
        guard let scanner else {
            scannerState = .driverMissing
            return
        }
        scannerState = .searching
        do {
            devices = try await scanner.listDevices()
            capabilitiesByDevice = [:]
            for device in devices {
                capabilitiesByDevice[device.id] = (try? await scanner.capabilities(device: device)) ?? .unknown
            }
            let remembered = UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
            if let device = devices.first(where: { $0.id == remembered }) ?? devices.first {
                select(device)
            } else if let missing = await Task.detached(operation: { FirmwareHelper.missingFirmware() }).value.first {
                scannerState = .firmwareMissing(missing)
            } else {
                scannerState = .notFound
            }
        } catch {
            scannerState = .notFound
            errorMessage = error.localizedDescription
        }
    }

    /// Choisit le scanner actif et adapte les réglages à ses capacités.
    public func select(_ device: ScannerDevice) {
        guard !isScanning else { return }
        capabilities = capabilitiesByDevice[device.id] ?? .unknown
        let adjusted = capabilities.adjusted(settings)
        if adjusted != settings { settings = adjusted }
        UserDefaults.standard.set(device.id, forKey: Self.selectedDeviceKey)
        scannerState = .ready(device)
    }

    /// Installe le firmware fourni par l'utilisateur puis relance la détection.
    public func installFirmware(from url: URL, for missing: MissingFirmware) async {
        do {
            try FirmwareHelper.install(url, for: missing)
            statusMessage = "Firmware installé pour le \(missing.productName)."
            errorMessage = nil
            await detectScanner()
        } catch {
            errorMessage = "Impossible d'installer le firmware : \(error.localizedDescription)"
        }
    }

    // MARK: - Numérisation

    /// Numérise le contenu du chargeur et ajoute les pages à la fin du document en cours.
    public func scan() async {
        guard let scanner, let device, !isScanning else { return }
        isScanning = true
        scannedInCurrentBatch = 0
        skippedInCurrentBatch = 0
        errorMessage = nil
        statusMessage = "Numérisation…"
        let batchDirectory = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let current = settings

        do {
            _ = try await scanner.scan(
                device: device,
                settings: current,
                supportedOptions: capabilities.options,
                outputDirectory: batchDirectory
            ) { [weak self] url in
                // Redressement et nettoyage avant la détection : un verso vide dont on voyait la transparence
                // redevient bien blanc.
                DocumentCleaner.processFile(at: url, resolution: current.resolution, deskew: current.deskew,
                                            clean: current.cleanBackground && current.colorMode != .lineart,
                                            strength: current.cleanStrength)
                let blank = current.skipBlankPages && Self.isBlankPage(at: url, threshold: current.blankThreshold)
                // La file principale est FIFO : l'ordre recto / verso des pages est conservé.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.scannedInCurrentBatch += 1
                        if blank {
                            self.skippedInCurrentBatch += 1
                        } else {
                            self.pages.append(ScanPage(imageURL: url, resolution: current.resolution))
                        }
                        self.statusMessage = "Page \(self.scannedInCurrentBatch) numérisée…"
                    }
                }
            }
            // Laisse passer les dernières mises à jour de pages publiées sur le main actor.
            await Task.yield()
            statusMessage = summary(skipped: skippedInCurrentBatch)
        } catch let error as ScannerError where error == .cancelled {
            statusMessage = "Numérisation annulée."
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    nonisolated private static func isBlankPage(at url: URL, threshold: Double) -> Bool {
        guard let image = ImageLoader.cgImage(at: url) else { return false }
        return BlankPageDetector.isBlank(image, threshold: threshold)
    }

    private func summary(skipped: Int) -> String {
        let kept = scannedInCurrentBatch - skipped
        var text = "\(kept) page\(kept > 1 ? "s" : "") ajoutée\(kept > 1 ? "s" : "")"
        if skipped > 0 {
            text += ", \(skipped) page\(skipped > 1 ? "s" : "") blanche\(skipped > 1 ? "s" : "") ignorée\(skipped > 1 ? "s" : "")"
        }
        return text + "."
    }

    public func cancelScan() {
        scanner?.cancel()
    }

    // MARK: - Édition

    public func rotate(_ page: ScanPage, clockwise: Bool = true) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        if clockwise { pages[index].rotateClockwise() } else { pages[index].rotateCounterClockwise() }
    }

    public func delete(_ page: ScanPage) {
        pages.removeAll { $0.id == page.id }
    }

    /// Déplace `pageID` à la position de `targetID` (glisser-déposer).
    public func move(pageID: UUID, before targetID: UUID) {
        guard pageID != targetID,
              let from = pages.firstIndex(where: { $0.id == pageID }),
              let to = pages.firstIndex(where: { $0.id == targetID })
        else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }

    public func clear() {
        pages.removeAll()
        cachedSuggestion = nil
        statusMessage = nil
        errorMessage = nil
        try? FileManager.default.removeItem(at: workDirectory)
    }

    // MARK: - Nommage automatique

    /// Émetteurs et intitulés appris au fil des enregistrements.
    @Published public private(set) var namingMemory = NamingMemory.load()
    private var cachedSuggestion: (key: [String], suggestion: NameSuggestion)?

    /// Propose `AAMMJJ-EMETTEUR-Intitule` d'après les deux premières pages ; le résultat est réutilisé
    /// tant que ces pages ne changent pas (rouvrir la fenêtre d'enregistrement ne relance pas l'analyse).
    public func suggestName() async -> NameSuggestion {
        let key = pages.prefix(2).map { "\($0.id)-\($0.rotation)" }
        if let cached = cachedSuggestion, cached.key == key { return cached.suggestion }
        let suggestion = await DocumentAnalyzer.suggest(pages: Array(pages.prefix(2)), memory: namingMemory)
        cachedSuggestion = (key, suggestion)
        return suggestion
    }

    /// Mémorise le nom validé pour mieux reconnaître cet émetteur la prochaine fois.
    public func recordNaming(proposed: DocumentName, final: DocumentName) {
        namingMemory.record(proposed: proposed, final: final)
        namingMemory.save()
    }

    // MARK: - Enregistrement

    public func save(to url: URL, ocr: Bool) async -> Bool {
        guard !pages.isEmpty, !isSaving else { return false }
        isSaving = true
        saveProgress = 0
        errorMessage = nil
        statusMessage = ocr ? "Reconnaissance du texte et création du PDF…" : "Création du PDF…"
        let snapshot = pages

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            Result {
                try PDFBuilder.build(pages: snapshot, to: url, ocr: ocr) { done, total in
                    Task { @MainActor in self.saveProgress = Double(done) / Double(total) }
                }
            }
        }.value

        isSaving = false
        switch result {
        case .success:
            statusMessage = "Enregistré : \(url.lastPathComponent)"
            return true
        case .failure(let error):
            statusMessage = nil
            errorMessage = error.localizedDescription
            return false
        }
    }
}
