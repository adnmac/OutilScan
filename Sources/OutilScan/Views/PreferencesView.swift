import AppKit
import OutilScanCore
import SwiftUI

/// Clés des préférences, partagées entre l'app et la fenêtre Préférences.
enum PreferenceKey {
    static let language = "appLanguage"
    static let appearance = "appAppearance"
}

/// Applique langue et apparence ; appelé à chaque rendu de la fenêtre principale, donc avant ses textes.
enum Preferences {
    static func apply(language: AppLanguage, appearance: AppAppearance) {
        L10n.language = language

        let wanted: NSAppearance? = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApplication.shared.appearance?.name != wanted?.name {
            NSApplication.shared.appearance = wanted
        }

        // Les menus standard de macOS (Édition, Fenêtre…) suivent cette langue au prochain lancement.
        let defaults = UserDefaults.standard
        let current = defaults.array(forKey: "AppleLanguages") as? [String]
        if language == .system {
            if defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        } else if current?.first != language.rawValue {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Fenêtre Préférences (menu OutilScan > Réglages…, ⌘,).
struct PreferencesView: View {
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system
    @AppStorage(PreferenceKey.appearance) private var appearance = AppAppearance.system

    var body: some View {
        let _ = Preferences.apply(language: language, appearance: appearance)
        Form {
            Section(L10n.tr("Apparence")) {
                Picker(L10n.tr("Apparence"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(L10n.tr("Langue")) {
                Picker(L10n.tr("Langue"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(L10n.tr("Les menus de macOS (Fichier, Édition…) changeront de langue au prochain lancement."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Reconstruit la fenêtre dans la nouvelle langue dès le changement.
        .id(language)
    }
}
