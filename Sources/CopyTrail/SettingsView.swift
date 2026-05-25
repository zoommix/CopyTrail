import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var config: Config
    var onClose: () -> Void

    @State private var draft: Int = Config.defaultMaxHistory
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section {
                    Stepper(value: $draft, in: Config.minMaxHistory...Config.maxMaxHistory) {
                        HStack {
                            Text("Max history size")
                            Spacer()
                            TextField("", value: $draft, format: .number)
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Section("Global hotkey") {
                    KeyboardShortcuts.Recorder(for: .showCopyTrail)
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
        .frame(width: 360)
        .onAppear { draft = config.maxHistory }
    }

    private func save() {
        guard draft >= Config.minMaxHistory, draft <= Config.maxMaxHistory else {
            error = "Must be between \(Config.minMaxHistory) and \(Config.maxMaxHistory)"
            return
        }
        config.setMaxHistory(draft)
        onClose()
    }
}
