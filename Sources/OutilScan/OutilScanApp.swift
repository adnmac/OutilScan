import AppKit
import OutilScanCore
import SwiftUI

@main
struct OutilScanApp: App {
    @StateObject private var session = ScanSession()
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system

    init() {
        // Nécessaire quand l'exécutable est lancé hors d'un paquet .app (swift run).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("OutilScan") {
            // Appliqué avant de construire les vues, pour qu'elles s'affichent directement dans la bonne langue.
            let _ = Preferences.apply(language: language, appearance: appearance)
            ContentView()
                .environmentObject(session)
                .environment(\.locale, L10n.locale)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
                // Changer de langue reconstruit toute la fenêtre avec les nouveaux textes.
                .id(language)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.tr("Numériser")) { Task { await session.scan() } }
                    .keyboardShortcut("n")
                    .disabled(session.device == nil || session.isScanning)
            }
        }

        Settings {
            PreferencesView()
        }
    }
}
