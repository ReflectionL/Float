import SwiftUI
import AppKit

// Give the window a neutral initial responder, instead of AppKit choosing and
// selecting the first editable title. This runs only when the view is attached;
// later activation and explicit keyboard navigation retain their normal focus.
struct InitialWorkspaceFocus: NSViewRepresentable {
    var configureUndo: (UndoManager) -> Void = { _ in }
    func makeNSView(context: Context) -> InitialWorkspaceFocusView {
        let view = InitialWorkspaceFocusView()
        view.configureUndo = configureUndo
        return view
    }

    func updateNSView(_ nsView: InitialWorkspaceFocusView, context: Context) {}
}

final class InitialWorkspaceFocusView: NSView {
    var configureUndo: (UndoManager) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, configuredWindow !== window else { return }
        configuredWindow = window
        if let manager = window.undoManager { configureUndo(manager) }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
        setAccessibilityElement(false)
    }
}
