import AppKit

enum OverlayCorner: String, CaseIterable {
    case topRight, topLeft, bottomLeft, bottomRight

    var title: String {
        switch self {
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var isTop: Bool { self == .topRight || self == .topLeft }
    var isRight: Bool { self == .topRight || self == .bottomRight }
}

/// Borderless, click-through panel that floats above everything.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true        // never steals a click from the app below
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws one line of text with its *ink* bounds pinned to a known inset, so the
/// caller can position the visible digits exactly rather than positioning a box
/// that has font leading baked into it.
final class DigitsView: NSView {

    private var line: CTLine?
    private var textOrigin: NSPoint = .zero
    private var shadowBlur: CGFloat = 0
    private(set) var inkSize: NSSize = .zero

    override var isFlipped: Bool { false }

    /// - Parameter reference: a string of the same length used to measure the
    ///   box, instead of measuring `attributed` itself. Digit shapes have
    ///   different ink widths even in a monospaced-digit font (a `1` inks about
    ///   13 pt narrower than a `0` at 90 pt), so measuring the live string would
    ///   move the anchored edge every time the time changed.
    /// - Returns: the size the enclosing window should be.
    func setContent(_ attributed: NSAttributedString,
                    reference: NSAttributedString,
                    inset: CGFloat,
                    shadowBlur: CGFloat) -> NSSize {
        // Tight bounds around the drawn glyphs, relative to the text origin.
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(reference), nil)

        self.line = CTLineCreateWithAttributedString(attributed)
        self.shadowBlur = shadowBlur
        inkSize = ink.size
        // Draw such that the reference ink rect's lower-left corner lands at
        // (inset, inset). Digit advances are equal, so the real glyphs line up.
        textOrigin = NSPoint(x: inset - ink.origin.x, y: inset - ink.origin.y)
        needsDisplay = true

        return NSSize(width: ink.width + inset * 2, height: ink.height + inset * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let line, let context = NSGraphicsContext.current?.cgContext else { return }
        // Core Text ignores the .shadow attribute, so apply it to the context.
        if shadowBlur > 0 {
            context.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.25),
                              blur: shadowBlur,
                              color: NSColor.black.withAlphaComponent(0.55).cgColor)
        }
        context.textMatrix = .identity
        context.textPosition = textOrigin
        CTLineDraw(line, context)
    }
}

final class OverlayController {

    /// Font size as a fraction of the screen height.
    private let fontScale: CGFloat = 0.10
    /// Gap from the digits to the left/right edge of the usable screen area.
    private let horizontalMargin: CGFloat = 16
    /// Gap from the digits to the top/bottom edge of the usable screen area.
    /// Equal to `horizontalMargin` so all four corners inset identically.
    private let verticalMargin: CGFloat = 16
    private let restingAlpha: CGFloat = 0.45
    /// Slack around the text so the drop shadow isn't clipped by the window.
    private let shadowInset: CGFloat = 12

    private let panel = OverlayPanel()
    private let digits = DigitsView()
    private var text = "00:00"
    private var hoverTimer: Timer?
    private var isHiddenByHover = false

    private(set) var isEnabled = false
    private(set) var corner: OverlayCorner = .topRight

    init() {
        panel.contentView = digits
        panel.alphaValue = restingAlpha

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)

        layout()
    }

    // MARK: - Content

    func setText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        layout()
    }

    func setCorner(_ newCorner: OverlayCorner) {
        corner = newCorner
        layout()
    }

    // MARK: - Enable / disable

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            layout()
            panel.orderFrontRegardless()
            startHoverTracking()
        } else {
            stopHoverTracking()
            panel.orderOut(nil)
        }
    }

    // MARK: - Layout

    @objc private func screensChanged() { layout() }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }

        let fontSize = max(24, (screen.frame.height * fontScale).rounded())
        // There's no backing plate, so a soft shadow is what keeps the digits
        // legible over light content.
        let blur = fontSize * 0.06

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        // Measure against the same layout with every digit as a zero, so the
        // anchored corner does not shift as the digits change.
        let reference = String(text.map { $0.isNumber ? "0" : $0 })
        let size = digits.setContent(NSAttributedString(string: text, attributes: attributes),
                                     reference: NSAttributedString(string: reference, attributes: attributes),
                                     inset: shadowInset,
                                     shadowBlur: blur)

        // visibleFrame excludes the menu bar and the Dock, so the margins are
        // measured against the area actually available. The shadow inset is
        // added back so the glyphs, not the window, sit at the margin.
        let visible = screen.visibleFrame
        let x = corner.isRight
            ? visible.maxX - horizontalMargin - digits.inkSize.width - shadowInset
            : visible.minX + horizontalMargin - shadowInset
        let y = corner.isTop
            ? visible.maxY - verticalMargin - digits.inkSize.height - shadowInset
            : visible.minY + verticalMargin - shadowInset

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        digits.frame = NSRect(origin: .zero, size: size)
    }

    // MARK: - Hover

    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkHover() }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        isHiddenByHover = false
        panel.alphaValue = restingAlpha
    }

    /// The panel ignores mouse events, so it gets no enter/exit callbacks.
    /// Poll the cursor position instead.
    private func checkHover() {
        let inside = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        guard inside != isHiddenByHover else { return }
        isHiddenByHover = inside
        NSAnimationContext.runAnimationGroup { context in
            context.duration = inside ? 0.12 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = inside ? 0 : restingAlpha
        }
    }
}
