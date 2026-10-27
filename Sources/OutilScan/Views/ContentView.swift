import OutilScanCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ScanSession
    @ViewState private var showingSaveSheet = false
    @ViewState private var confirmingClear = false

    var body: some View {
        NavigationSplitView {
            SettingsPanel()
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if session.pages.isEmpty {
                    emptyState
                } else {
                    PageGridView()
                }
                statusBar
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Tout effacer", systemImage: "trash")
                    }
                    .disabled(session.pages.isEmpty || session.isScanning || session.isSaving)

                    Button {
                        showingSaveSheet = true
                    } label: {
                        Label("Enregistrer le PDF", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s")
                    .disabled(session.pages.isEmpty || session.isScanning || session.isSaving)
                }
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveSheet()
        }
        .confirmationDialog("Effacer toutes les pages numérisées ?", isPresented: $confirmingClear) {
            Button("Effacer", role: .destructive) { session.clear() }
        }
        .task { await session.detectScanner() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucune page", systemImage: "doc.viewfinder")
        } description: {
            Text("Place tes documents dans le chargeur, face imprimée vers le bas, puis clique sur « Numériser ».")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if session.isScanning || session.isSaving {
                ProgressView().controlSize(.small)
            }
            if session.isSaving {
                ProgressView(value: session.saveProgress).frame(width: 120)
            }
            if let error = session.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).foregroundStyle(.primary)
            } else if let status = session.statusMessage {
                Text(status).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(session.pages.count) page\(session.pages.count > 1 ? "s" : "")")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
