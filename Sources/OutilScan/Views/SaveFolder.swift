import AppKit
import SwiftUI

/// Dossier d'enregistrement des PDF, partagé entre la barre latérale et la fenêtre d'enregistrement.
enum SaveFolder {
    static let storageKey = "saveDirectory"

    static var defaultPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    }

    /// Chemin lisible : le dossier personnel est abrégé en « ~ ».
    static func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Ouvre le sélecteur de dossier ; renvoie le nouveau chemin, ou nil si l'utilisateur annule.
    static func choose(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        panel.prompt = "Choisir"
        panel.message = "Dossier où enregistrer les PDF numérisés"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Section de la barre latérale : dossier actuel, bouton pour le changer et pour l'ouvrir dans le Finder.
struct SaveFolderSection: View {
    @AppStorage(SaveFolder.storageKey) private var directoryPath = SaveFolder.defaultPath

    var body: some View {
        Section("Enregistrement") {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(SaveFolder.displayPath(directoryPath))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(directoryPath)
                } icon: {
                    Image(systemName: folderExists ? "folder.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(folderExists ? Color.accentColor : .orange)
                }
                if !folderExists {
                    Text("Ce dossier n'existe plus : choisis-en un autre.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Choisir…") {
                        if let path = SaveFolder.choose(startingAt: directoryPath) { directoryPath = path }
                    }
                    Button("Ouvrir") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: directoryPath, isDirectory: true))
                    }
                    .disabled(!folderExists)
                }
            }
        }
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
