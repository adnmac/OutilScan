import AppKit
import OutilScanCore
import SwiftUI

@main
struct OutilScanApp: App {
    @StateObject private var session = ScanSession()

    init() {
        // Nécessaire quand l'exécutable est lancé hors d'un paquet .app (swift run).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("OutilScan") {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Numériser") { Task { await session.scan() } }
                    .keyboardShortcut("n")
                    .disabled(session.device == nil || session.isScanning)
            }
        }
    }
}
