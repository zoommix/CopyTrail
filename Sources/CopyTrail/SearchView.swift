import SwiftUI

struct SearchView: View {
    @ObservedObject var store: HistoryStore
    var onRestore: (HistoryEntry) -> Void
    var onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selection: HistoryEntry.ID?

    private let rowHeight: CGFloat = 24
    private let maxVisibleRows = 12

    private var filtered: [HistoryEntry] {
        store.search(query)
    }

    private var listHeight: CGFloat {
        let count = max(filtered.count, 1)
        return CGFloat(min(count, maxVisibleRows)) * rowHeight + 8
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $query,
                onUp:    { move(by: -1) },
                onDown:  { move(by: 1) },
                onCommit: { restoreSelected() },
                onCancel: { onDismiss() }
            )
            .frame(height: 24)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if filtered.isEmpty {
                Text(query.isEmpty ? "No clipboard history yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                            row(for: entry, index: idx)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: listHeight)
                    .onChange(of: selection) { _, newValue in
                        if let id = newValue {
                            withAnimation(.none) { proxy.scrollTo(id) }
                        }
                    }
                }
            }
        }
        .background(cmdNumberShortcuts)
        .frame(width: 380)
        .onAppear {
            selection = filtered.first?.id
        }
        .onChange(of: query) { _, _ in
            selection = filtered.first?.id
        }
    }

    private func row(for entry: HistoryEntry, index idx: Int) -> some View {
        HStack(spacing: 8) {
            Text(entry.preview)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if idx < 9 {
                Text("⌘\(idx + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else if idx == 9 {
                Text("⌘0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .tag(entry.id)
        .onTapGesture {
            selection = entry.id
            restoreSelected()
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
