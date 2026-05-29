import AppKit
import SwiftUI

struct PreviewContentView: View {
    let entry: HistoryEntry
    let store: HistoryStore

    private let fontSize: CGFloat = 13

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(VisualEffectView(material: .menu))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .text:
            textPreview
        case .image:
            imagePreview
        }
    }

    private var textPreview: some View {
        ScrollView {
            Text(entry.text ?? "")
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let url = store.imageURL(for: entry),
           let nsImage = NSImage(contentsOf: url) {
            ScrollView {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
        } else {
            Text("Image not available")
                .foregroundStyle(.secondary)
                .font(.system(size: fontSize))
                .padding(10)
        }
    }
}
