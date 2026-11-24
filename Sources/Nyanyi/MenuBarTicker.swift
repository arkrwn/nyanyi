import AppKit
import QuartzCore

final class MenuBarTicker {
    private weak var statusButton: NSStatusBarButton?
    private var containerView: NSView?
    private var textLayer: CATextLayer?
    private var currentText: String = ""

    private let maxWidth: CGFloat = 240
    private let barHeight: CGFloat = 22
    private let fontSize: CGFloat = 12
    private let scrollSpeed: CGFloat = 28 // points per second
    private let pauseDuration: CFTimeInterval = 1.5

    init(statusButton: NSStatusBarButton) {
        self.statusButton = statusButton
    }

    func start() {
        guard let button = statusButton else { return }
        button.image = nil
        button.title = ""

        let container = NSView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: barHeight))
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let tl = CATextLayer()
        tl.fontSize = fontSize
        tl.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        tl.foregroundColor = NSColor.labelColor.cgColor
        tl.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        tl.alignmentMode = .left
        tl.isWrapped = false

        container.layer?.addSublayer(tl)
        button.addSubview(container)
        button.frame = container.frame

        self.containerView = container
        self.textLayer = tl
    }

    func stop() {
        textLayer?.removeAllAnimations()
        containerView?.removeFromSuperview()
        containerView = nil
        textLayer = nil
        currentText = ""
    }

    func updateText(_ text: String) {
        let display = text.isEmpty ? "♪ Nyanyi" : "♪ \(text)"
        guard display != currentText else { return }
        currentText = display

        guard let tl = textLayer, let container = containerView,
              let button = statusButton else { return }

        tl.removeAllAnimations()

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = ceil((display as NSString).size(withAttributes: attrs).width)
        let yOffset = (barHeight - fontSize - 3) / 2

        tl.string = display
        tl.foregroundColor = NSColor.labelColor.cgColor

        let visibleWidth = min(textWidth + 12, maxWidth)
        container.frame = NSRect(x: 0, y: 0, width: visibleWidth, height: barHeight)
        button.frame = container.frame

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tl.frame = CGRect(x: 6, y: yOffset, width: textWidth + 20, height: fontSize + 4)
        CATransaction.commit()

        let overflow = textWidth - (maxWidth - 12)
        if overflow > 4 {
            addScrollAnimation(layer: tl, overflow: overflow, yOffset: yOffset)
        }
    }

    private func addScrollAnimation(layer: CATextLayer, overflow: CGFloat, yOffset: CGFloat) {
        let scrollTime = CFTimeInterval(overflow / scrollSpeed)
        let totalDuration = pauseDuration + scrollTime + pauseDuration + scrollTime

        let anim = CAKeyframeAnimation(keyPath: "position.x")
        let startX = 6 + layer.bounds.width / 2
        let endX = startX - overflow

        let t0 = 0.0
        let t1 = pauseDuration / totalDuration
        let t2 = (pauseDuration + scrollTime) / totalDuration
        let t3 = (pauseDuration + scrollTime + pauseDuration) / totalDuration
        let t4 = 1.0

        anim.values = [startX, startX, endX, endX, startX]
        anim.keyTimes = [
            NSNumber(value: t0),
            NSNumber(value: t1),
            NSNumber(value: t2),
            NSNumber(value: t3),
            NSNumber(value: t4)
        ]
        anim.duration = totalDuration
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false

        layer.add(anim, forKey: "tickerScroll")
    }
}
