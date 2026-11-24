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
    private var screenObserver: Any?

    private static let floatingSize = NSSize(width: 440, height: 340)
    private static let cornerSize = NSSize(width: 380, height: 220)
    private static let subtitleHeight: CGFloat = 96
    private static let cornerMargin: CGFloat = 16
    private static let subtitleVerticalMargin: CGFloat = 36

    init(viewModel: LyricsViewModel, displaySettings: DisplaySettings) {
        self.displaySettings = displaySettings

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.floatingSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // Stay visible above all apps including full-screen spaces/videos
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 280, height: 80)
        panel.maxSize = NSSize(width: 1600, height: 800)

        let hostingView = NSHostingView(
            rootView: ContentView(viewModel: viewModel, displaySettings: displaySettings)
        )
        panel.contentView = hostingView

        super.init(window: panel)

        positionBottomRight(size: Self.floatingSize)
        observeScreenChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        removeDragMonitor()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let mode = self.displaySettings.mode
            if mode == .subtitleBottom || mode == .subtitleTop || mode == .corner {
                self.applyDisplayMode(mode)
            }
        }
    }

    func applyDisplayMode(_ mode: DisplayMode) {
        guard let panel = window as? OverlayPanel else { return }
        removeDragMonitor()

        // Ensure full-screen visibility properties remain active across mode switches
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        switch mode {
        case .floating:
            panel.styleMask.insert(.resizable)
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
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
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            snapToCorner(displaySettings.corner, animated: true)
            installDragMonitor()

        case .subtitleBottom:
            panel.styleMask.remove(.resizable)
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            snapToSubtitleEdge(top: false, animated: true)

        case .subtitleTop:
            panel.styleMask.remove(.resizable)
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            snapToSubtitleEdge(top: true, animated: true)

        case .menuBar:
            break
        }
    }

    private func snapToSubtitleEdge(top: Bool, animated: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let panel = window else { return }
        let vf = screen.visibleFrame
        let fullFrame = screen.frame
        let width = min(max(vf.width * 0.72, 560), 1100)
        let height = Self.subtitleHeight
        let x = fullFrame.midX - (width / 2.0)

        let y: CGFloat
        if top {
            // Respect menu bar height when visible, or sit near top edge in full-screen
            y = vf.maxY - height - 14
        } else {
            y = max(vf.minY + 18, fullFrame.minY + Self.subtitleVerticalMargin)
        }

        let targetFrame = NSRect(x: x, y: y, width: width, height: height)
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
