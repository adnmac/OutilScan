import Foundation

public struct ScannerDevice: Identifiable, Equatable, Hashable {
    /// Identifiant SANE, par exemple `fujitsu:libusb:001:004`.
    public let id: String
    public let vendor: String
    public let model: String

    public var displayName: String { "\(vendor) \(model)" }
}

public enum ScannerError: LocalizedError, Equatable {
    case scanimageMissing
    case noDocuments
    case coverOpen
    case jammed
    case busy
    case cancelled
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .scanimageMissing:
            return "Le pilote SANE est introuvable. Installe-le avec : brew install sane-backends"
        case .noDocuments:
            return "Le chargeur est vide. Place les documents face imprimée vers le bas et réessaie."
        case .coverOpen:
            return "Le capot du scanner est ouvert ou le scanner est en veille."
        case .jammed:
            return "Bourrage papier : retire les feuilles coincées puis relance."
        case .busy:
            return "Le scanner est occupé. Quitte ScanSnap Home ou VueScan, puis réessaie."
        case .cancelled:
            return "Numérisation annulée."
        case .other(let message):
            return message
        }
    }

    /// Traduit les messages d'erreur de `scanimage` en erreurs compréhensibles.
    public static func from(stderr: String) -> ScannerError {
        let text = stderr.lowercased()
        if text.contains("out of documents") || text.contains("no documents") { return .noDocuments }
        if text.contains("cover") { return .coverOpen }
        if text.contains("jammed") { return .jammed }
        if text.contains("busy") { return .busy }
        let lastLine = stderr.split(separator: "\n").last.map(String.init) ?? "Erreur inconnue"
        return .other("Erreur du scanner : \(lastLine)")
    }
}

/// Pilote le scanner via l'outil en ligne de commande `scanimage` (SANE).
public final class SaneScanner {
    public static let candidatePaths = [
        "/opt/homebrew/bin/scanimage",
        "/usr/local/bin/scanimage",
    ]

    public let executableURL: URL
    private var currentProcess: Process?
    private var wasCancelled = false

    public init?() {
        // Une app lancée depuis le Finder n'hérite pas du PATH du shell : on cherche aux emplacements Homebrew.
        guard let path = Self.candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }
        executableURL = URL(fileURLWithPath: path)
    }

    public func listDevices() async throws -> [ScannerDevice] {
        let result = try await run(["-f", "%d|%v|%m%n"])
        return Self.parseDeviceList(result.stdout)
    }

    static func parseDeviceList(_ output: String) -> [ScannerDevice] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            return ScannerDevice(id: parts[0], vendor: parts[1], model: parts[2])
        }
    }

    /// Options, sources, modes et résolutions que le backend accepte pour ce périphérique.
    public func capabilities(device: ScannerDevice) async throws -> ScannerCapabilities {
        let result = try await run(["-d", device.id, "-A"])
        return ScannerCapabilities.parse(result.stdout)
    }

    /// Numérise toutes les feuilles du chargeur. `onPage` est appelé dès qu'une page est complètement écrite.
    public func scan(
        device: ScannerDevice,
        settings: ScanSettings,
        supportedOptions: Set<String>,
        outputDirectory: URL,
        onPage: @escaping (URL) -> Void
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let pattern = outputDirectory.appendingPathComponent("page-%04d.tif").path
        let args = ["-d", device.id]
            + settings.scanimageArguments(supportedOptions: supportedOptions)
            + ["--format=tiff", "--batch=\(pattern)", "--batch-print"]

        var pages: [URL] = []
        let lock = NSLock()
        wasCancelled = false
        let result = try await run(args) { line in
            // --batch-print écrit le nom du fichier sur stdout une fois la page terminée.
            let path = line.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return }
            let url = URL(fileURLWithPath: path)
            lock.withLock { pages.append(url) }
            onPage(url)
        }

        if wasCancelled { throw ScannerError.cancelled }
        let scanned = lock.withLock { pages }
        // En mode batch, scanimage s'arrête quand le chargeur est vide : ce n'est une erreur que si rien n'a été numérisé.
        if scanned.isEmpty {
            throw ScannerError.from(stderr: result.stderr)
        }
        if result.status != 0 && !result.stderr.lowercased().contains("out of documents")
            && !result.stderr.contains("Batch terminated") {
            // Page partielle possible (bourrage en cours de lot) : on garde les pages valides et on signale l'erreur.
            throw ScannerError.from(stderr: result.stderr)
        }
        return scanned
    }

    public func cancel() {
        wasCancelled = true
        // SIGINT laisse scanimage terminer proprement la page en cours et libérer le périphérique.
        currentProcess?.interrupt()
    }

    // MARK: - Exécution

    public struct CommandResult {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    private func run(_ arguments: [String], onLine: ((String) -> Void)? = nil) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector(onLine: onLine)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStdout(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStderr(handle.availableData)
        }

        currentProcess = process
        defer { currentProcess = nil }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                collector.appendStdout(outPipe.fileHandleForReading.readDataToEndOfFile())
                collector.appendStderr(errPipe.fileHandleForReading.readDataToEndOfFile())
                collector.flush()
                continuation.resume(returning: CommandResult(
                    status: proc.terminationStatus,
                    stdout: collector.stdout,
                    stderr: collector.stderr
                ))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Accumule la sortie d'un processus et découpe stdout en lignes complètes.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var pendingLine = Data()
    private let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)?) { self.onLine = onLine }

    var stdout: String { lock.withLock { String(decoding: stdoutData, as: UTF8.self) } }
    var stderr: String { lock.withLock { String(decoding: stderrData, as: UTF8.self) } }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        var lines: [String] = []
        lock.withLock {
            stdoutData.append(data)
            pendingLine.append(data)
            while let newline = pendingLine.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pendingLine[pendingLine.startIndex..<newline], as: UTF8.self))
                pendingLine.removeSubrange(pendingLine.startIndex...newline)
            }
        }
        lines.forEach { onLine?($0) }
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { stderrData.append(data) }
    }

    func flush() {
        let rest = lock.withLock { () -> String in
            defer { pendingLine.removeAll() }
            return String(decoding: pendingLine, as: UTF8.self)
        }
        if !rest.isEmpty { onLine?(rest) }
    }
}
