import AppKit
import OutilScanCore
import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var session: ScanSession

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Scanner") {
                    scannerStatus
                }

                Section("Numérisation") {
                    Picker("Face", selection: $session.settings.side) {
                        ForEach(session.capabilities.sides) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Couleur", selection: $session.settings.colorMode) {
                        ForEach(session.capabilities.colorModes) { Text($0.label).tag($0) }
                    }

                    Picker("Résolution", selection: $session.settings.resolution) {
                        ForEach(resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                    }

                    Picker("Format", selection: $session.settings.paperSize) {
                        ForEach(PaperSize.allCases) { Text($0.label).tag($0) }
                    }

                    // Redressement fait par l'app : disponible pour tous les scanners.
                    Toggle("Redresser les pages", isOn: $session.settings.deskew)
                }

                if session.settings.colorMode != .lineart {
                    Section("Nettoyage") {
                        Toggle("Nettoyer le fond", isOn: $session.settings.cleanBackground)
                        if session.settings.cleanBackground {
                            Picker("Intensité", selection: $session.settings.cleanStrength) {
                                ForEach(DocumentCleaner.Strength.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("Supprime les ombres du pli et le texte du verso vu par transparence.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Pages blanches") {
                    Toggle("Ignorer les pages blanches", isOn: $session.settings.skipBlankPages)
                    if session.settings.skipBlankPages {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sensibilité")
                                Spacer()
                                TextField("Sensibilité", value: sensitivityPercent, format: .number.precision(.fractionLength(0)))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 48)
                                Text("%")
                            }
                            Slider(value: sensitivityPercent, in: 0...100, step: 1) {
                                Text("Sensibilité")
                            } minimumValueLabel: {
                                Text("Faible").font(.caption)
                            } maximumValueLabel: {
                                Text("Forte").font(.caption)
                            }
                            .labelsHidden()
                            Text("Une sensibilité forte ignore aussi les pages presque vides.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SaveFolderSection()
            }
            .formStyle(.grouped)

            scanButton
                .padding()
        }
    }

    private var resolutions: [Int] {
        session.capabilities.resolutions.isEmpty ? ScanSettings.resolutions : session.capabilities.resolutions
    }

    /// Curseur et champ partagent la même valeur ; une saisie hors limites est ramenée entre 0 et 100 %.
    private var sensitivityPercent: Binding<Double> {
        Binding(
            get: { session.settings.blankSensitivity },
            set: { session.settings.blankSensitivity = $0 }
        )
    }

    @ViewBuilder
    private var scannerStatus: some View {
        switch session.scannerState {
        case .searching:
            HStack {
                ProgressView().controlSize(.small)
                Text("Recherche du scanner…")
            }
        case .driverMissing:
            VStack(alignment: .leading, spacing: 6) {
                Label("Pilote SANE absent", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Installe-le dans le Terminal :")
                    .font(.caption)
                Text("brew install sane-backends")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                refreshButton
            }
        case .notFound:
            VStack(alignment: .leading, spacing: 6) {
                Label("Scanner non détecté", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Branche le S1500 en USB et ouvre son capot pour l'allumer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                refreshButton
            }
        case .firmwareMissing(let missing):
            VStack(alignment: .leading, spacing: 6) {
                Label("Firmware manquant", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Le \(missing.productName) est branché, mais SANE a besoin du fichier « \(missing.fileName) » fourni par Fujitsu avec ScanSnap Manager.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Importer le firmware…") { importFirmware(missing) }
                refreshButton
            }
        case .ready(let device):
            HStack {
                if session.devices.count > 1 {
                    Picker("Scanner", selection: deviceSelection) {
                        ForEach(session.devices) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden()
                    .disabled(session.isScanning)
                } else {
                    Label(device.displayName, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                refreshButton.labelStyle(.iconOnly)
            }
        }
    }

    private var deviceSelection: Binding<String> {
        Binding(
            get: { session.device?.id ?? "" },
            set: { id in
                if let device = session.devices.first(where: { $0.id == id }) { session.select(device) }
            }
        )
    }

    private func importFirmware(_ missing: MissingFirmware) {
        let panel = NSOpenPanel()
        panel.message = "Choisis le fichier \(missing.fileName) (copié depuis une installation de ScanSnap Manager)."
        panel.prompt = "Installer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await session.installFirmware(from: url, for: missing) }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await session.detectScanner() }
        } label: {
            Label("Actualiser", systemImage: "arrow.clockwise")
        }
        .disabled(session.isScanning || session.scannerState == .searching)
    }

    @ViewBuilder
    private var scanButton: some View {
        if session.isScanning {
            Button(role: .cancel) {
                session.cancelScan()
            } label: {
                Label("Annuler", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        } else {
            Button {
                Task { await session.scan() }
            } label: {
                Label(session.pages.isEmpty ? "Numériser" : "Numériser et ajouter", systemImage: "scanner")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(session.device == nil || session.isSaving)
        }
    }
}
