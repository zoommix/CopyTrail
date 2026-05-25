import AppKit
import SwiftUI

/// SwiftUI wrapper around AppKit's NSSearchField. This gives the popover a
/// proper native search bar (magnifying glass icon, rounded bezel, clear
/// button) and forwards arrow / return / escape key presses to the parent
/// view so list navigation works while the field has focus.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onUp: () -> Void
    var onDown: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search clipboard history…"
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        // Become first responder as soon as we're in a window.
        DispatchQueue.main.async {
            if let window = field.window {
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onUp()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
