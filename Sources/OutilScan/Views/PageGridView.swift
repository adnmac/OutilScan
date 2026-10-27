import AppKit
import OutilScanCore
import SwiftUI

struct PageGridView: View {
    @EnvironmentObject private var session: ScanSession
    @ViewState private var dropTarget: UUID?
    @ViewState private var enlargedPage: ScanPage?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                    PageCell(page: page, number: index + 1, isDropTarget: dropTarget == page.id)
                        .onTapGesture(count: 2) { enlargedPage = page }
                        .draggable(page.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
                            session.move(pageID: id, before: page.id)
                            return true
                        } isTargeted: { targeted in
                            dropTarget = targeted ? page.id : (dropTarget == page.id ? nil : dropTarget)
                        }
                }
            }
            .padding(20)
        }
        .sheet(item: $enlargedPage) { page in
            PagePreview(startPageID: page.id)
        }
    }
}

private struct PageCell: View {
    @EnvironmentObject private var session: ScanSession
    let page: ScanPage
    let number: Int
    let isDropTarget: Bool
    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Thumbnail(url: page.imageURL)
                .rotationEffect(.degrees(Double(page.rotation)))
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isDropTarget ? Color.accentColor : .clear, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    if hovering { actions.padding(6) }
                }
                .animation(.easeInOut(duration: 0.2), value: page.rotation)

            Text("Page \(number)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Pivoter à droite") { session.rotate(page) }
            Button("Pivoter à gauche") { session.rotate(page, clockwise: false) }
            Divider()
            Button("Supprimer la page", role: .destructive) { session.delete(page) }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            iconButton("rotate.left", help: "Pivoter à gauche") { session.rotate(page, clockwise: false) }
            iconButton("rotate.right", help: "Pivoter à droite") { session.rotate(page) }
            iconButton("trash", help: "Supprimer la page") { session.delete(page) }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Aperçu en grand, avec navigation de page en page (boutons ou flèches ← → du clavier).
private struct PagePreview: View {
    @EnvironmentObject private var session: ScanSession
    @Environment(\.dismiss) private var dismiss
    let startPageID: UUID
    @ViewState private var currentID: UUID?
    @ViewState private var image: CGImage?

    private var index: Int? { session.pages.firstIndex { $0.id == (currentID ?? startPageID) } }
    private var page: ScanPage? { index.map { session.pages[$0] } }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let image, let page {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(Double(page.rotation)))
                        .shadow(radius: 2)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button { go(by: -1) } label: {
                    Label("Précédente", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled((index ?? 0) == 0)

                Text(index.map { "Page \($0 + 1) sur \(session.pages.count)" } ?? "")
                    .monospacedDigit()
                    .frame(minWidth: 110)

                Button { go(by: 1) } label: {
                    Label("Suivante", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled((index ?? 0) >= session.pages.count - 1)

                Divider().frame(height: 18)

                Button { if let page { session.rotate(page, clockwise: false) } } label: {
                    Image(systemName: "rotate.left")
                }
                .help("Pivoter à gauche")
                Button { if let page { session.rotate(page) } } label: {
                    Image(systemName: "rotate.right")
                }
                .help("Pivoter à droite")
                Button(role: .destructive) { deleteCurrent() } label: {
                    Image(systemName: "trash")
                }
                .help("Supprimer la page")

                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 820)
        .task(id: page?.imageURL) {
            guard let url = page?.imageURL else { return }
            image = nil
            image = await Task.detached(priority: .userInitiated) {
                ImageLoader.thumbnail(at: url, maxPixelSize: 1800)
            }.value
        }
    }

    private func go(by offset: Int) {
        guard let index else { return }
        let target = index + offset
        guard session.pages.indices.contains(target) else { return }
        currentID = session.pages[target].id
    }

    /// Supprime la page affichée et passe à la suivante (ou à la précédente s'il s'agissait de la dernière).
    private func deleteCurrent() {
        guard let index, let page else { return }
        let next = session.pages.indices.contains(index + 1) ? session.pages[index + 1].id
            : (index > 0 ? session.pages[index - 1].id : nil)
        session.delete(page)
        if let next { currentID = next } else { dismiss() }
    }
}

/// « Suivante › » : l'icône après le texte.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Vignette chargée en arrière-plan pour ne pas bloquer l'interface pendant la numérisation.
private struct Thumbnail: View {
    let url: URL
    @ViewState private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .shadow(radius: 1)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                ImageLoader.thumbnail(at: url)
            }.value
        }
    }
}
