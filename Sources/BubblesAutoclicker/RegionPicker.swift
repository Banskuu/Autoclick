#if os(macOS)
import AppKit
import BubblesCore

@MainActor
final class RegionPickerController {
    static let shared = RegionPickerController()
    private var window: NSWindow?

    func pick(shape: AreaShape, completion: @escaping (ClickRect?) -> Void) {
        guard window == nil else { return }
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let window = NSWindow(contentRect: union, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RegionPickerView(frame: CGRect(origin: .zero, size: union.size), shape: shape) { [weak self] rect in
            self?.window?.orderOut(nil)
            self?.window = nil
            completion(rect)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
    }
}

final class RegionPickerView: NSView {
    private var startLocal: CGPoint?
    private var currentLocal: CGPoint?
    private var startCG: CGPoint?
    private var currentCG: CGPoint?
    private let shape: AreaShape
    private let completion: (ClickRect?) -> Void

    init(frame: CGRect, shape: AreaShape, completion: @escaping (ClickRect?) -> Void) {
        self.shape = shape
        self.completion = completion
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let startLocal, let currentLocal else {
            drawLabel("Drag to select click region. Esc cancels.")
            return
        }
        let rect = localRect(startLocal, currentLocal)
        NSColor.clear.setFill(); rect.fill()
        NSColor.systemYellow.setStroke()
        let path = NSBezierPath(rect: rect); path.lineWidth = 3; path.stroke()
        drawLabel("\(Int(abs((currentCG?.x ?? 0) - (startCG?.x ?? 0)))) x \(Int(abs((currentCG?.y ?? 0) - (startCG?.y ?? 0))))")
    }

    override func mouseDown(with event: NSEvent) {
        startLocal = event.locationInWindow
        currentLocal = startLocal
        startCG = event.cgEvent?.location ?? CGEvent(source: nil)?.location
        currentCG = startCG
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentLocal = event.locationInWindow
        currentCG = event.cgEvent?.location ?? CGEvent(source: nil)?.location
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentLocal = event.locationInWindow
        currentCG = event.cgEvent?.location ?? CGEvent(source: nil)?.location
        guard let a = startCG, let b = currentCG else { completion(nil); return }
        var x1 = a.x, x2 = b.x, y1 = a.y, y2 = b.y
        if shape == .square {
            let dx = x2 - x1, dy = y2 - y1
            let side = min(abs(dx), abs(dy))
            x2 = x1 + (dx < 0 ? -side : side)
            y2 = y1 + (dy < 0 ? -side : side)
        }
        completion(ClickRect(xMin: x1, xMax: x2, yMin: y1, yMax: y2))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion(nil) } else { super.keyDown(with: event) }
    }

    private func localRect(_ a: CGPoint, _ b: CGPoint) -> NSRect {
        NSRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }

    private func drawLabel(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .bold), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (bounds.width-size.width)/2, y: bounds.height-60), withAttributes: attrs)
    }
}
#endif
