import Foundation

/// Scanner Fujitsu branché en USB mais invisible pour SANE, faute de fichier firmware.
public struct MissingFirmware: Equatable {
    public let productName: String
    /// Fichier attendu par le backend `epjitsu`, par ex. `1300_0C26.nal`.
    public var fileName: String { destination.lastPathComponent }
    /// Emplacement indiqué dans `epjitsu.conf`.
    public let destination: URL
}

/// Les ScanSnap S300 / S1300 / S1100 (backend `epjitsu`) doivent recevoir leur firmware à chaque mise sous tension.
/// Ce fichier appartient à Fujitsu et n'est pas fourni avec SANE : il vient de l'installation de ScanSnap Manager.
public enum FirmwareHelper {
    public static let fujitsuVendorID = 0x04C5

    static let configCandidates = [
        "/opt/homebrew/etc/sane.d/epjitsu.conf",
        "/usr/local/etc/sane.d/epjitsu.conf",
    ]

    /// Copie de sauvegarde : après un `brew upgrade`, le chemin du firmware change et l'app le réinstalle seule.
    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutilScan/firmware", isDirectory: true)
    }

    /// Firmware attendu par identifiant de produit USB, d'après `epjitsu.conf`.
    static func parseConfig(_ text: String) -> [Int: URL] {
        var result: [Int: URL] = [:]
        var pendingFirmware: URL?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("firmware ") {
                pendingFirmware = URL(fileURLWithPath: String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("usb "), let firmware = pendingFirmware {
                let parts = line.split(separator: " ")
                if parts.count >= 3, let product = Int(parts[2].replacingOccurrences(of: "0x", with: ""), radix: 16) {
                    result[product] = firmware
                }
                pendingFirmware = nil
            }
        }
        return result
    }

    struct USBDevice: Equatable {
        var name: String
        var vendorID: Int
        var productID: Int
    }

    /// Analyse la sortie de `ioreg -p IOUSB -l -w0`.
    static func parseIORegistry(_ text: String) -> [USBDevice] {
        var devices: [USBDevice] = []
        var current: USBDevice?
        func value(_ line: Substring) -> String {
            guard let equal = line.range(of: " = ") else { return "" }
            return line[equal.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        for line in text.split(separator: "\n") {
            if line.contains("+-o ") {
                if let device = current { devices.append(device) }
                current = USBDevice(name: "", vendorID: -1, productID: -1)
            } else if line.contains("\"USB Product Name\" = ") {
                current?.name = value(line)
            } else if line.contains("\"idVendor\" = ") {
                current?.vendorID = Int(value(line)) ?? -1
            } else if line.contains("\"idProduct\" = ") {
                current?.productID = Int(value(line)) ?? -1
            }
        }
        if let device = current { devices.append(device) }
        return devices
    }

    /// Scanners Fujitsu branchés dont le firmware est absent. Réinstalle d'abord la copie de sauvegarde si elle existe.
    public static func missingFirmware() -> [MissingFirmware] {
        guard let configPath = configCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let config = try? String(contentsOfFile: configPath, encoding: .utf8),
              let registry = runIOReg()
        else { return [] }

        let expected = parseConfig(config)
        return parseIORegistry(registry)
            .filter { $0.vendorID == fujitsuVendorID }
            .compactMap { device -> MissingFirmware? in
                guard let destination = expected[device.productID],
                      !FileManager.default.fileExists(atPath: destination.path)
                else { return nil }
                let backup = backupDirectory.appendingPathComponent(destination.lastPathComponent)
                if FileManager.default.fileExists(atPath: backup.path),
                   (try? copy(backup, to: destination)) != nil {
                    return nil
                }
                return MissingFirmware(productName: device.name, destination: destination)
            }
    }

    /// Installe le firmware choisi par l'utilisateur et en garde une copie de sauvegarde.
    public static func install(_ source: URL, for missing: MissingFirmware) throws {
        try copy(source, to: missing.destination)
        try? copy(source, to: backupDirectory.appendingPathComponent(missing.fileName))
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func runIOReg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-p", "IOUSB", "-l", "-w0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
