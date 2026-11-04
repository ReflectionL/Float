import AppKit

@MainActor
enum EditingBoundary {
    static var isComposing: Bool {
        isComposing(NSApp.keyWindow?.firstResponder)
    }

    static func isComposing(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextView)?.hasMarkedText() == true
    }

    // A vertically growing SwiftUI TextField still uses AppKit's field editor,
    // where insertNewline normally ends editing. Keep its selection, undo and
    // binding notifications while explicitly inserting a line break instead.
    static func insertLineBreak(in responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView,
              textView.isEditable, !textView.hasMarkedText() else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    // Finish the native field editor before exit/import/export. This lets the
    // input method and SwiftUI deliver the final text before persistence runs.
    @discardableResult
    static func endEditing() -> Bool {
        guard let window = NSApp.keyWindow else { return true }
        return window.makeFirstResponder(nil)
    }
}
