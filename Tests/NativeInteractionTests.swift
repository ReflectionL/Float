import AppKit
import SwiftUI

// In-process view tests: hidden windows only. No system input is synthesized,
// no window is shown, and no running user application is controlled.
@main
struct NativeInteractionTests {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        exercise(.dropBefore)
        exercise(.dropAfter)
        exercise(.clickOnly)
        exercise(.escape)
        exercise(.outsideViewport)
        exercise(.scrolledDrop)
        testComposition()
        testLineBreak()
        print("PASS: native mouse tracking, insertion, cancellation, edge scrolling, marked text and field-editor line breaks")
    }

    enum Scenario { case dropBefore, dropAfter, clickOnly, escape, outsideViewport, scrolledDrop }

    @MainActor
    static func exercise(_ scenario: Scenario) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 1472, height: 600))
        scroll.documentView = document
        window.contentView = scroll
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var drops: [(UUID, UUID, Bool)] = []
        var columns: [ThreadDropHostingView<EmptyView>] = []
        for index in ids.indices {
            let column = ThreadDropHostingView(rootView: EmptyView())
            column.sizingOptions = []
            column.frame = NSRect(x: index * 368, y: 0, width: 368, height: 600)
            column.threadID = ids[index]
            column.canMove = { ids.contains($0) }
            column.move = { source, after in drops.append((source, ids[index], after)) }
            document.addSubview(column)
            columns.append(column)
        }
        let sourceIndex = scenario == .dropAfter ? 0 : 1
        let handle = ThreadDragHandleView(frame: NSRect(x: 324, y: 520, width: 28, height: 24))
        handle.threadID = ids[sourceIndex]
        // Hiding the glyph after the pointer leaves the header must not
        // remove the native surface or interrupt an ongoing drag.
        handle.showsGlyph = false
        columns[sourceIndex].addSubview(handle)
        document.layoutSubtreeIfNeeded()
        precondition(ThreadDragGeometry.scrollViewport(scroll, toward: NSPoint(x: 754, y: 300)))
        precondition(scroll.contentView.bounds.minX > 0)
        precondition(ThreadDragGeometry.scrollViewport(scroll, toward: NSPoint(x: 6, y: 300)))
        precondition(scroll.contentView.bounds.minX == 0)
        scroll.contentView.scroll(to: NSPoint(x: 712, y: 0))
        precondition(!ThreadDragGeometry.scrollViewport(scroll, toward: NSPoint(x: 754, y: 300)))
        precondition(scroll.contentView.bounds.minX == 712)
        scroll.contentView.scroll(to: NSPoint(x: scenario == .scrolledDrop ? 500 : 0, y: 0))
        let start = handle.convert(NSPoint(x: 14, y: 12), to: nil)
        let target: NSPoint
        switch scenario {
        case .dropAfter, .scrolledDrop: target = NSPoint(x: 700, y: 300)
        case .outsideViewport: target = NSPoint(x: 1100, y: 300)
        default: target = NSPoint(x: 30, y: 300)
        }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        handle.mouseDown(with: mouse(.leftMouseDown, start))
        if scenario != .clickOnly {
            handle.mouseDragged(with: mouse(.leftMouseDragged, target))
        }
        if scenario == .escape {
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                          charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            handle.keyDown(with: escape)
        }
        handle.mouseUp(with: mouse(.leftMouseUp, scenario == .clickOnly ? start : target))
        switch scenario {
        case .dropBefore:
            precondition(drops.count == 1, "A quick drag must produce exactly one drop")
            precondition(drops[0].0 == ids[1] && drops[0].1 == ids[0] && !drops[0].2)
        case .dropAfter:
            precondition(drops.count == 1)
            precondition(drops[0].0 == ids[0] && drops[0].1 == ids[1] && drops[0].2)
        case .scrolledDrop:
            precondition(drops.count == 1)
            precondition(drops[0].0 == ids[1] && drops[0].1 == ids[3] && !drops[0].2)
        case .clickOnly, .escape, .outsideViewport:
            precondition(drops.isEmpty, "Cancelled/outside/click-only input must not reorder")
        }
        handle.cancelDrag()
        window.close()
    }
    @MainActor
    static func testComposition() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        precondition(!EditingBoundary.isComposing(textView))
        textView.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 0, length: 0))
        precondition(EditingBoundary.isComposing(textView), "Marked candidate text must block early commit")
        precondition(!EditingBoundary.insertLineBreak(in: textView), "Return must stay with the input method while composing")
        textView.insertText("中文", replacementRange: textView.markedRange())
        precondition(!EditingBoundary.isComposing(textView))
        precondition(textView.string == "中文")
    }

    @MainActor
    static func testLineBreak() {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        editor.isFieldEditor = true
        editor.allowsUndo = true
        editor.string = "第一行第二行"
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        precondition(EditingBoundary.insertLineBreak(in: editor))
        precondition(editor.string == "第一行\n第二行", "Return must insert at the caret even in a field editor")
        precondition(editor.selectedRange() == NSRange(location: 4, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        precondition(EditingBoundary.insertLineBreak(in: editor))
        precondition(editor.string == "\n\n第二行", "Return must replace selected text")
        precondition(!EditingBoundary.insertLineBreak(in: NSResponder()))
    }

}
