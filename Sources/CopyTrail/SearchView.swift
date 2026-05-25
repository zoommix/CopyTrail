import AppKit
import SwiftUI

struct SearchView: View {
    @ObservedObject var store: HistoryStore
    var onRestore: (HistoryEntry) -> Void
    var onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selection: HistoryEntry.ID?
    @State private var hoveredID: HistoryEntry.ID?

    /// Native menu metrics: NSMenu rows are 22pt, item font is 13pt.
    private let rowHeight: CGFloat = 22
    private let menuFontSize: CGFloat = 13
    private let maxVisibleRows = 12

    private var filtered: [HistoryEntry] {
        store.search(query)
    }

    private var listHeight: CGFloat {
        let count = max(filtered.count, 1)
        return CGFloat(min(count, maxVisibleRows)) * rowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if filtered.isEmpty {
                Text(query.isEmpty ? "No clipboard history yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .font(.system(size: menuFontSize))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                            row(for: entry, index: idx)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, rowHeight)
                    .frame(height: listHeight)
                    .onChange(of: selection) { _, newValue in
                        if let id = newValue {
                            withAnimation(.none) { proxy.scrollTo(id) }
                        }
                    }
                }
            }
        }
        .background(VisualEffectView(material: .menu))
        .background(cmdNumberShortcuts)
        .frame(width: 360)
        .onAppear {
            selection = filtered.first?.id
        }
        .onChange(of: query) { _, _ in
            selection = filtered.first?.id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SearchField(
                text: $query,
                onUp: { move(by: -1) },
                onDown: { move(by: 1) },
                onCommit: { restoreSelected() },
                onCancel: { onDismiss() }
            )
            .frame(height: 22)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func row(for entry: HistoryEntry, index idx: Int) -> some View {
        HStack(spacing: 8) {
            if entry.kind == .image, let url = store.imageURL(for: entry) {
                thumbnail(at: url)
            }
            Text(entry.preview)
                .font(.system(size: menuFontSize))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            shortcutLabel(idx: idx)
            deleteButton(for: entry)
                .opacity(hoveredID == entry.id ? 1 : 0)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .tag(entry.id)
        .onTapGesture {
            selection = entry.id
            restoreSelected()
        }
        .onHover { hovering in
            if hovering {
                hoveredID = entry.id
            } else if hoveredID == entry.id {
                hoveredID = nil
            }
        }
    }

    private func deleteButton(for entry: HistoryEntry) -> some View {
        Button {
            store.remove(entry.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Remove from history")
    }

    @ViewBuilder
    private func thumbnail(at url: URL) -> some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
                .frame(width: 28, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private func shortcutLabel(idx: Int) -> some View {
        if idx < 9 {
            Text("⌘\(idx + 1)")
                .font(.system(size: 12, design: .default))
                .foregroundStyle(.tertiary)
        } else if idx == 9 {
            Text("⌘0")
                .font(.system(size: 12, design: .default))
                .foregroundStyle(.tertiary)
        }
    }

    private var cmdNumberShortcuts: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Button("") { restoreAt(index: i) }
                    .keyboardShortcut(KeyEquivalent(Character("\((i + 1) % 10)")), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private func move(by delta: Int) {
        let items = filtered
        guard !items.isEmpty else {
            selection = nil
            return
        }
        let currentIdx = items.firstIndex(where: { $0.id == selection }) ?? -1
        var next: Int
        if currentIdx < 0 {
            next = delta > 0 ? 0 : items.count - 1
        } else {
            next = currentIdx + delta
        }
        next = max(0, min(items.count - 1, next))
        selection = items[next].id
    }

    private func restoreSelected() {
        let items = filtered
        let target: HistoryEntry?
        if let sel = selection, let entry = items.first(where: { $0.id == sel }) {
            target = entry
        } else {
            target = items.first
        }
        if let t = target {
            onRestore(t)
        } else {
            onDismiss()
        }
    }

    private func restoreAt(index: Int) {
        let items = filtered
        guard index < items.count else { return }
        onRestore(items[index])
    }
}
