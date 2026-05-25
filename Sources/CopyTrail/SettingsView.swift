import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var config: Config
    @ObservedObject var history: HistoryStore
    var onClose: () -> Void

    @State private var draftMaxHistory: Int = Config.defaultMaxHistory
    @State private var draftMaxImageMB: Int = Config.defaultMaxImageMB
    @State private var error: String?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section {
                    Stepper(
                        value: $draftMaxHistory,
                        in: Config.minMaxHistory...Config.maxMaxHistory,
                        step: 100
                    ) {
                        labeledNumber(title: "Max history size", binding: $draftMaxHistory)
                    }
                    Stepper(value: $draftMaxImageMB, in: Config.minMaxImageMB...Config.maxMaxImageMB) {
                        labeledNumber(
                            title: "Max image size (MB)",
                            binding: $draftMaxImageMB,
                            help: draftMaxImageMB == 0 ? "Images won't be captured" : nil
                        )
                    }
                }
                Section("Global hotkey") {
                    KeyboardShortcuts.Recorder(for: .showCopyTrail)
                }
                Section("History") {
                    HStack {
                        Text("\(history.entries.count) entries stored")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Text("Clear history…")
                        }
                        .disabled(history.entries.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onClose() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            draftMaxHistory = config.maxHistory
            draftMaxImageMB = config.maxImageMB
        }
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(history.entries.count) entries (text + images) will be removed. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func labeledNumber(title: String, binding: Binding<Int>, help: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("", value: binding, format: .number)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        guard
            draftMaxHistory >= Config.minMaxHistory,
            draftMaxHistory <= Config.maxMaxHistory
        else {
            error = "Max history must be \(Config.minMaxHistory)–\(Config.maxMaxHistory)"
            return
        }
        guard
            draftMaxImageMB >= Config.minMaxImageMB,
            draftMaxImageMB <= Config.maxMaxImageMB
        else {
            error = "Max image size must be \(Config.minMaxImageMB)–\(Config.maxMaxImageMB) MB"
            return
        }
        config.setMaxHistory(draftMaxHistory)
        config.setMaxImageMB(draftMaxImageMB)
        onClose()
    }
}
