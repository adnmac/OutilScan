import AppKit
import OutilScanCore
import SwiftUI

/// Enregistrement avec nommage `AAMMJJ-EMETTEUR-Intitule` proposé automatiquement d'après le contenu du document.
struct SaveSheet: View {
    @EnvironmentObject private var session: ScanSession
    @Environment(\.dismiss) private var dismiss

    @ViewState private var name = DocumentName()
    @ViewState private var suggestion: NameSuggestion?
    @ViewState private var isAnalyzing = true
    @ViewState private var showingCalendar = false
    @AppStorage(SaveFolder.storageKey) private var directoryPath = SaveFolder.defaultPath
    @AppStorage("revealAfterSave") private var revealAfterSave = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enregistrer le PDF").font(.title2.bold())

            Form {
                Section {
                    LabeledContent("Date") {
                        HStack(spacing: 10) {
                            TextField("AAMMJJ", text: $name.date)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 110, maxWidth: 130)
                            Button {
                                showingCalendar.toggle()
                            } label: {
                                Image(systemName: "calendar")
                            }
                            .buttonStyle(.borderless)
                            .help("Choisir la date dans un calendrier")
                            .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                                calendar
                            }
                            dateHint
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }

                    LabeledContent("Émetteur") {
                        HStack {
                            TextField("ex. CHU Lille", text: $name.issuer)
                                .textFieldStyle(.roundedBorder)
                            recentMenu(session.namingMemory.issuers) { name.issuer = $0 }
                        }
                    }

                    LabeledContent("Intitulé") {
                        HStack {
                            TextField("ex. Facture soins", text: $name.title)
                                .textFieldStyle(.roundedBorder)
                            recentMenu(session.namingMemory.titles) { name.title = $0 }
                        }
                    }
                } header: {
                    analysisStatus
                }
                .disabled(isAnalyzing)

                LabeledContent("Dossier") {
                    HStack {
                        Text(SaveFolder.displayPath(directoryPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choisir…", action: chooseDirectory)
                    }
                }

                Toggle("Reconnaissance de texte (OCR)", isOn: $session.settings.ocr)
                Toggle("Afficher dans le Finder après l'enregistrement", isOn: $revealAfterSave)
            }

            HStack(spacing: 6) {
                Image(systemName: "doc.fill").foregroundStyle(.secondary)
                Text(isAnalyzing ? "…" : destination.lastPathComponent)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Text("\(session.pages.count) page\(session.pages.count > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || name.fileName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task {
            let result = await session.suggestName()
            suggestion = result
            name = result.name
            isAnalyzing = false
        }
    }

    @ViewBuilder
    private var analysisStatus: some View {
        if isAnalyzing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Lecture du document…")
            }
        } else if suggestion?.source == .appleIntelligence {
            Label("Nom proposé par Apple Intelligence (sur ton Mac)", systemImage: "sparkles")
        } else {
            Label("Nom proposé d'après les mots-clés du document", systemImage: "text.magnifyingglass")
        }
    }

    /// Calendrier synchronisé avec le champ AAMMJJ ; il se referme dès qu'un jour est choisi.
    private var calendar: some View {
        let selection = Binding<Date>(
            get: { DocumentName.date(fromCode: name.date) ?? Date() },
            set: { newDate in
                name.date = DocumentName.code(for: newDate)
                showingCalendar = false
            }
        )
        return VStack(spacing: 8) {
            DatePicker("Date du document", selection: selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_BE"))
            Button("Aujourd'hui") { selection.wrappedValue = Date() }
                .buttonStyle(.link)
        }
        .padding(12)
    }

    @ViewBuilder
    private var dateHint: some View {
        if let date = DocumentName.date(fromCode: name.date) {
            let label = date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
            if suggestion?.dateFound == false && name.date == suggestion?.name.date {
                Text("\(label) — date du jour, aucune date trouvée")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        } else if !name.date.isEmpty {
            Text("Format attendu : AAMMJJ, par ex. 261012").font(.caption).foregroundStyle(.red)
        }
    }

    /// Menu des valeurs déjà utilisées, pour compléter en un clic.
    private func recentMenu(_ values: [String], select: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(values.prefix(25), id: \.self) { value in
                Button(value) { select(value) }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(values.isEmpty)
        .help("Déjà utilisés")
    }

    private var directoryURL: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }

    private var destination: URL {
        FileNaming.uniqueURL(directory: directoryURL, baseName: name.fileName)
    }

    private func chooseDirectory() {
        if let path = SaveFolder.choose(startingAt: directoryPath) { directoryPath = path }
    }

    private func save() {
        let url = destination
        let ocr = session.settings.ocr
        let reveal = revealAfterSave
        if let suggestion {
            session.recordNaming(proposed: suggestion.name, final: name)
        }
        dismiss()
        Task {
            if await session.save(to: url, ocr: ocr), reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
