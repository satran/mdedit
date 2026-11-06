import AppKit

/// A plain question with one action button and Cancel. True when the person pressed the action button.
enum ConfirmPrompt {
    static func ask(_ title: String, _ detail: String, _ button: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}
