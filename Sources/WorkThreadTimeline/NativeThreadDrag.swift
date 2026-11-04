import AppKit
import SwiftUI

@MainActor
private func traceDrag(_ message: String) {
    #if UI_TEST
    guard let path = Bundle.main.object(forInfoDictionaryKey: "XlineQAStorePath") as? String else { return }
    let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("drag.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        do { try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); try handle.close() } catch { }
    } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    #endif
}

enum ThreadDragGeometry {
    static func insertAfter(x: CGFloat, width: CGFloat) -> Bool { x > width / 2 }
    @MainActor
    @discardableResult
    static func scrollViewport(_ scroll: NSScrollView, toward windowPoint: NSPoint) -> Bool {
        guard let document = scroll.documentView else { return false }
        let clip = scroll.contentView
        guard document.bounds.width > clip.bounds.width + 1 else { return false }
        let point = clip.convert(windowPoint, from: nil)
        guard clip.bounds.insetBy(dx: -12, dy: 0).contains(point) else { return false }
        let delta = scrollDelta(x: point.x, visible: clip.bounds)
        let x = min(max(clip.bounds.minX + delta, document.bounds.minX), document.bounds.maxX - clip.bounds.width)
        guard abs(x - clip.bounds.minX) > 0.01 else { return false }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
        return true
    }

    static func scrollDelta(x: CGFloat, visible: CGRect) -> CGFloat {
        let edge: CGFloat = min(48, visible.width / 4)
        if x < visible.minX + edge { return -12 }
        if x > visible.maxX - edge { return 12 }
        return 0
    }
}

@MainActor
private protocol ThreadDropSurface: AnyObject {
    var surfaceView: NSView { get }
    var threadID: UUID { get }
    var canMove: (UUID) -> Bool { get }
    var move: (UUID, Bool) -> Void { get }
    func showInsertion(at x: CGFloat?)
}

@MainActor
private enum ThreadDragRegistry {
    private final class WeakSurface {
        weak var value: (any ThreadDropSurface)?
        init(_ value: any ThreadDropSurface) { self.value = value }
    }
    private static var surfaces: [WeakSurface] = []

    static func register(_ value: any ThreadDropSurface) {
        surfaces.removeAll { $0.value == nil || $0.value?.surfaceView === value.surfaceView }
        surfaces.append(WeakSurface(value))
    }

    static func target(for source: ThreadDragHandleView, at point: NSPoint) -> (any ThreadDropSurface)? {
        surfaces.compactMap(\.value).first {
            let view = $0.surfaceView
            return view.window === source.window && view.window != nil && !view.isHiddenOrHasHiddenAncestor
                && view.bounds.intersection(view.visibleRect).contains(view.convert(point, from: nil)) && $0.canMove(source.threadID)
        }
    }

    static func update(source: ThreadDragHandleView, at point: NSPoint) {
        clear()
        guard let target = target(for: source, at: point) else { return }
        target.showInsertion(at: target.surfaceView.convert(point, from: nil).x)
    }

    static func drop(source: ThreadDragHandleView, at point: NSPoint) {
        defer { clear() }
        guard let target = target(for: source, at: point), target.threadID != source.threadID else { return }
        let x = target.surfaceView.convert(point, from: nil).x
        traceDrag("drop \(source.threadID) onto \(target.threadID)")
        target.move(source.threadID, ThreadDragGeometry.insertAfter(x: x, width: target.surfaceView.bounds.width))
    }

    static func clear() { surfaces.compactMap(\.value).forEach { $0.showInsertion(at: nil) } }
}

/// Each column exposes its clipped native bounds for internal reordering. The
/// handle tracks AppKit mouse events directly; no text or external app drop can
/// accidentally reorder threads, and Escape/outside release cancel the move.
struct NativeThreadColumn<Content: View>: NSViewRepresentable {
    let threadID: UUID
    let canMove: (UUID) -> Bool
    let move: (UUID, Bool) -> Void
    let content: Content

    func makeNSView(context: Context) -> ThreadDropHostingView<Content> {
        let view = ThreadDropHostingView(rootView: content)
        view.sizingOptions = []
        configure(view)
        return view
    }
    func updateNSView(_ view: ThreadDropHostingView<Content>, context: Context) {
        view.rootView = content
        configure(view)
    }
    private func configure(_ view: ThreadDropHostingView<Content>) {
        view.threadID = threadID
        view.canMove = canMove
        view.move = move
    }
}

final class ThreadDropHostingView<Content: View>: NSHostingView<Content>, ThreadDropSurface {
    var threadID = UUID()
    var canMove: (UUID) -> Bool = { _ in false }
    var move: (UUID, Bool) -> Void = { _, _ in }
    var surfaceView: NSView { self }
    private var insertionLine: CALayer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { ThreadDragRegistry.register(self) }
    }
    func showInsertion(at x: CGFloat?) {
        guard let x else { insertionLine?.isHidden = true; return }
        wantsLayer = true
        if insertionLine == nil {
            let line = CALayer()
            line.cornerRadius = 1.5
            layer?.addSublayer(line)
            insertionLine = line
        }
        // The design system's indigo accent (AppTheme.Colors.accent), resolved
        // for the current appearance because a layer color does not adapt.
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        insertionLine?.backgroundColor = (isDark
            ? NSColor(srgbRed: 0x5F / 255, green: 0x6B / 255, blue: 0xE8 / 255, alpha: 1)
            : NSColor(srgbRed: 0x45 / 255, green: 0x53 / 255, blue: 0xD0 / 255, alpha: 1)).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        insertionLine?.isHidden = false
        insertionLine?.frame = CGRect(x: ThreadDragGeometry.insertAfter(x: x, width: bounds.width) ? bounds.width - 3 : 0,
                                      y: 0, width: 3, height: bounds.height)
        CATransaction.commit()
    }
}

struct NativeThreadDragHandle: NSViewRepresentable {
    let id: UUID
    let title: String
    let select: () -> Void
    var showsGlyph = true
    func makeNSView(context: Context) -> ThreadDragHandleView {
        let view = ThreadDragHandleView()
        configure(view)
        return view
    }
    func updateNSView(_ view: ThreadDragHandleView, context: Context) { configure(view) }
    static func dismantleNSView(_ view: ThreadDragHandleView, coordinator: ()) { view.cancelDrag() }
    private func configure(_ view: ThreadDragHandleView) {
        view.threadID = id
        view.select = select
        view.showsGlyph = showsGlyph
        view.toolTip = "Drag to reorder this thread"
        view.setAccessibilityLabel("Drag \(title) to reorder")
    }
}

final class ThreadDragHandleView: NSView {
    var threadID = UUID()
    var select: () -> Void = {}
    var showsGlyph = true {
        didSet { if oldValue != showsGlyph { needsDisplay = true } }
    }
    private var startPoint: NSPoint?
    private var lastPoint = NSPoint.zero
    private var dragging = false
    private var scrollTimer: Timer?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        guard showsGlyph || dragging || window?.firstResponder === self else { return }
        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for offset in [-3.0, 0.0, 3.0] {
            path.move(to: NSPoint(x: bounds.midX - 5, y: bounds.midY + offset))
            path.line(to: NSPoint(x: bounds.midX + 5, y: bounds.midY + offset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        select()
        window?.makeFirstResponder(self)
        startPoint = event.locationInWindow
        lastPoint = event.locationInWindow
        traceDrag("down \(threadID)")
    }
    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        lastPoint = event.locationInWindow
        guard dragging || hypot(lastPoint.x - startPoint.x, lastPoint.y - startPoint.y) >= 3 else { return }
        if !dragging {
            dragging = true
            NSCursor.closedHand.push()
            let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(scrollAtEdge), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
            scrollTimer = timer
        }
        ThreadDragRegistry.update(source: self, at: lastPoint)
    }
    override func mouseUp(with event: NSEvent) {
        let shouldDrop = dragging
        cancelDrag()
        if shouldDrop { ThreadDragRegistry.drop(source: self, at: event.locationInWindow) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelDrag() } else { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { cancelDrag(); needsDisplay = true; return true }
    func cancelDrag() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        startPoint = nil
        if dragging { NSCursor.pop() }
        dragging = false
        ThreadDragRegistry.clear()
    }
    @objc private func scrollAtEdge() {
        guard window?.isKeyWindow == true else { cancelDrag(); return }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.bounds.width > scroll.contentView.bounds.width + 1 {
                if ThreadDragGeometry.scrollViewport(scroll, toward: lastPoint) {
                    ThreadDragRegistry.update(source: self, at: lastPoint)
                }
                return
            }
            ancestor = view.superview
        }
    }
}
