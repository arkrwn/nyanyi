import AppKit
import SwiftUI
import Combine
import NyanyiCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSWindowController {
    private let displaySettings: DisplaySettings
    private var dragEndMonitor: Any?

    private static let floatingSize = NSSize(width: 440, height: 340)
    private static let cornerSize = NSSize(width: 380, height: 220)
    private static let cornerMargin: CGFloat = 16

    init(viewModel: LyricsViewModel, displaySettings: DisplaySettings) {
        self.displaySettings = displaySettings

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.floatingSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 280, height: 150)
        panel.maxSize = NSSize(width: 900, height: 800)

        let hostingView = NSHostingView(
            rootView: ContentView(viewModel: viewModel, displaySettings: displaySettings)
        )
        panel.contentView = hostingView

        super.init(window: panel)

        positionBottomRight(size: Self.floatingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        removeDragMonitor()
    }

    func applyDisplayMode(_ mode: DisplayMode) {
        guard let panel = window as? OverlayPanel else { return }
        removeDragMonitor()

        switch mode {
        case .floating:
            panel.styleMask.insert(.resizable)
            panel.minSize = NSSize(width: 280, height: 150)
            panel.maxSize = NSSize(width: 900, height: 800)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let newFrame = NSRect(origin: panel.frame.origin, size: Self.floatingSize)
                panel.animator().setFrame(newFrame, display: true)
            }

        case .corner:
            panel.styleMask.remove(.resizable)
            snapToCorner(displaySettings.corner, animated: true)
            installDragMonitor()

        case .menuBar:
            break
        }
    }

    private func installDragMonitor() {
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, self.displaySettings.mode == .corner,
                  let panel = self.window else { return event }
            if event.window == panel {
                let nearest = self.nearestCorner(for: panel.frame)
                self.displaySettings.corner = nearest
                self.snapToCorner(nearest, animated: true)
            }
            return event
        }
    }

    private func removeDragMonitor() {
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
    }

    private func nearestCorner(for frame: NSRect) -> CornerPosition {
        guard let screen = NSScreen.main else { return .bottomRight }
        let sf = screen.visibleFrame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let midX = sf.midX
        let midY = sf.midY

        if center.x < midX {
            return center.y >= midY ? .topLeft : .bottomLeft
        } else {
            return center.y >= midY ? .topRight : .bottomRight
        }
    }

    func snapToCorner(_ corner: CornerPosition, animated: Bool) {
        guard let screen = NSScreen.main, let panel = window else { return }
        let sf = screen.visibleFrame
        let size = Self.cornerSize
        let m = Self.cornerMargin

        let origin: NSPoint
        switch corner {
        case .topLeft:
            origin = NSPoint(x: sf.minX + m, y: sf.maxY - size.height - m)
        case .topRight:
            origin = NSPoint(x: sf.maxX - size.width - m, y: sf.maxY - size.height - m)
        case .bottomLeft:
            origin = NSPoint(x: sf.minX + m, y: sf.minY + m)
        case .bottomRight:
            origin = NSPoint(x: sf.maxX - size.width - m, y: sf.minY + m)
        }

        let targetFrame = NSRect(origin: origin, size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func positionBottomRight(size: NSSize) {
        guard let screen = NSScreen.main, let window = window else { return }
        let sf = screen.visibleFrame
        let x = sf.maxX - size.width - 24
        let y = sf.minY + 24
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
