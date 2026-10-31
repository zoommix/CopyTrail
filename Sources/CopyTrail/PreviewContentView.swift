import AppKit
import SwiftUI

struct PreviewContentView: View {
    let entry: HistoryEntry
    let store: HistoryStore

    static let fontSize: CGFloat = 13

    /// Text as shown (blank lines and whitespace at either end trimmed);
    /// PreviewPanelController measures this same string.
    static func displayText(for entry: HistoryEntry) -> String {
        (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            Text(Self.displayText(for: entry))
                .font(.system(size: Self.fontSize))
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
                // Never upscale: PreviewPanelController sizes the panel for at most 1:1.
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: CGFloat(entry.imageWidth ?? Int(nsImage.size.width)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        } else {
            Text("Image not available")
                .foregroundStyle(.secondary)
                .font(.system(size: Self.fontSize))
                .padding(10)
        }
    }
}
