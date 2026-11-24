import AppKit
import SwiftUI
import Combine
import NyanyiCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSWindowController {
    private let viewModel: LyricsViewModel
    private let displaySettings: DisplaySettings
    var isManuallyHidden: Bool = false {
        didSet { updateVisibilityForPlayState() }
    }
    private var dragMonitor: Any?
    private var screenObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var hasPositionedSubtitle = false

    // Re-calibrated smaller base dimensions so Small / Medium / Large feel sleek and unobtrusive
    private static let baseFloatingSize = NSSize(width: 410, height: 300)
    private static let baseCornerSize = NSSize(width: 340, height: 195)
    private static let cornerMargin: CGFloat = 14
    private static let subtitleBottomMargin: CGFloat = 32

    init(viewModel: LyricsViewModel, displaySettings: DisplaySettings) {
        self.viewModel = viewModel
        self.displaySettings = displaySettings

        let initialSize = Self.scaledSize(Self.baseFloatingSize, for: displaySettings.size)
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // Stay visible above all apps including full-screen spaces/videos
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 220, height: 22)
        panel.maxSize = NSSize(width: 3840, height: 1200)

        let hv = NSHostingView(
            rootView: ContentView(viewModel: viewModel, displaySettings: displaySettings)
        )
        panel.contentView = hv

        super.init(window: panel)

        positionBottomRight(size: initialSize)
        observeScreenChanges()
        observeEmptyStateForClickThrough()
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

    private static func scaledSize(_ base: NSSize, for size: OverlaySize) -> NSSize {
        let factor = CGFloat(size.scaleFactor)
        return NSSize(width: round(base.width * factor), height: round(base.height * factor))
    }

    /// Re-calibrated static fixed dimensions for Subtitle (Movie Style) mode per OverlaySize (Small, Medium, Large).
    private static func subtitleStaticSize(for size: OverlaySize) -> NSSize {
        switch size {
        case .small:
            return NSSize(width: 340, height: 60)
        case .medium:
            return NSSize(width: 450, height: 74)
        case .large:
            return NSSize(width: 570, height: 90)
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
            if mode == .corner || mode == .bottomNavbar {
                self.applyDisplayMode(mode)
            }
        }
    }

    private func observeEmptyStateForClickThrough() {
        viewModel.$isPlaying
            .combineLatest(viewModel.$trackTitle, displaySettings.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateVisibilityForPlayState()
            }
            .store(in: &cancellables)
    }

    func updateVisibilityForPlayState() {
        guard let panel = window as? OverlayPanel else { return }
        guard displaySettings.mode != .menuBar else { return }

        let shouldAutoHideOnPause = (displaySettings.mode != .bottomNavbar) || displaySettings.bottomNavbarAutoHide
        let shouldShow: Bool
        if isManuallyHidden || viewModel.trackTitle.isEmpty {
            shouldShow = false
        } else if shouldAutoHideOnPause {
            shouldShow = viewModel.isPlaying
        } else {
            shouldShow = true
        }
        if shouldShow {
            panel.ignoresMouseEvents = false
            if !panel.isVisible || panel.alphaValue < 1.0 {
                if !panel.isVisible {
                    panel.alphaValue = 0.0
                    panel.orderFrontRegardless()
                }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1.0
                }
            }
        } else {
            panel.ignoresMouseEvents = true
            if panel.isVisible && panel.alphaValue > 0.0 {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    guard let self, let p = self.window as? OverlayPanel else { return }
                    let autoHide = (self.displaySettings.mode != .bottomNavbar) || self.displaySettings.bottomNavbarAutoHide
                    let stillShouldHide = self.isManuallyHidden || self.viewModel.trackTitle.isEmpty || (autoHide && !self.viewModel.isPlaying)
                    if stillShouldHide {
                        p.orderOut(nil)
                    }
                })
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    func applyDisplayMode(_ mode: DisplayMode) {
        guard let panel = window as? OverlayPanel else { return }
        removeDragMonitor()

        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let sizeSetting = displaySettings.size

        switch mode {
        case .floating:
            panel.styleMask.insert(.resizable)
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.minSize = NSSize(width: 240, height: 130)
            panel.maxSize = NSSize(width: 1200, height: 900)
            let targetSize = Self.scaledSize(Self.baseFloatingSize, for: sizeSetting)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let newFrame = NSRect(origin: panel.frame.origin, size: targetSize)
                panel.animator().setFrame(newFrame, display: true)
            }

        case .corner:
            panel.styleMask.remove(.resizable)
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            snapToCorner(displaySettings.corner, animated: true)
            installCornerDragMonitor()

        case .subtitle:
            panel.styleMask.remove(.resizable)
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            applyStaticSubtitleFrame(initialPlacement: !hasPositionedSubtitle)
            hasPositionedSubtitle = true
            installSubtitleDragMonitor()

        case .bottomNavbar:
            panel.styleMask.remove(.resizable)
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.hasShadow = true
            snapToBottomNavbar(animated: true)

        case .menuBar:
            break
        }
    }

    /// Snaps the overlay to the very bottom edge of the screen with 100% screen width and exact Apple Menu Bar height.
    private func snapToBottomNavbar(animated: Bool) {
        guard let panel = window as? OverlayPanel,
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let fullFrame = screen.frame
        let appleMenuBarHeight = max(28, NSStatusBar.system.thickness)
        let targetFrame = NSRect(
            x: fullFrame.minX,
            y: fullFrame.minY,
            width: fullFrame.width,
            height: appleMenuBarHeight
        )

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func applyStaticSubtitleFrame(initialPlacement: Bool) {
        guard let panel = window as? OverlayPanel,
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let targetSize = Self.subtitleStaticSize(for: displaySettings.size)
        let sf = screen.visibleFrame

        let centerX: CGFloat
        let centerY: CGFloat

        if initialPlacement {
            if let savedX = UserDefaults.standard.object(forKey: "subtitleCenterX") as? Double,
               let savedY = UserDefaults.standard.object(forKey: "subtitleCenterY") as? Double {
                centerX = CGFloat(savedX)
                centerY = CGFloat(savedY)
            } else {
                centerX = sf.midX
                centerY = sf.minY + Self.subtitleBottomMargin + (targetSize.height / 2.0)
            }
        } else {
            centerX = panel.frame.midX
            centerY = panel.frame.midY
        }

        let originX = min(max(round(centerX - targetSize.width / 2.0), sf.minX + 8), sf.maxX - targetSize.width - 8)
        let originY = min(max(round(centerY - targetSize.height / 2.0), sf.minY + 8), sf.maxY - targetSize.height - 8)
        let targetFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: targetSize)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Drag Monitors

    private func installSubtitleDragMonitor() {
        var dragStartMouseLocation: NSPoint?
        var dragStartWindowOrigin: NSPoint?

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, self.displaySettings.mode == .subtitle,
                  let panel = self.window else { return event }
            guard event.window == panel else { return event }

            switch event.type {
            case .leftMouseDown:
                dragStartMouseLocation = NSEvent.mouseLocation
                dragStartWindowOrigin = panel.frame.origin
            case .leftMouseDragged:
                if let startMouse = dragStartMouseLocation, let startOrigin = dragStartWindowOrigin {
                    let currentMouse = NSEvent.mouseLocation
                    let newOrigin = NSPoint(
                        x: startOrigin.x + (currentMouse.x - startMouse.x),
                        y: startOrigin.y + (currentMouse.y - startMouse.y)
                    )
                    panel.setFrameOrigin(newOrigin)
                }
            case .leftMouseUp:
                dragStartMouseLocation = nil
                dragStartWindowOrigin = nil
                UserDefaults.standard.set(Double(panel.frame.midX), forKey: "subtitleCenterX")
                UserDefaults.standard.set(Double(panel.frame.midY), forKey: "subtitleCenterY")
            default:
                break
            }
            return event
        }
    }

    private func installCornerDragMonitor() {
        var dragStartMouseLocation: NSPoint?
        var dragStartWindowOrigin: NSPoint?

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, self.displaySettings.mode == .corner,
                  let panel = self.window else { return event }
            guard event.window == panel else { return event }

            switch event.type {
            case .leftMouseDown:
                dragStartMouseLocation = NSEvent.mouseLocation
                dragStartWindowOrigin = panel.frame.origin
            case .leftMouseDragged:
                if let startMouse = dragStartMouseLocation, let startOrigin = dragStartWindowOrigin {
                    let currentMouse = NSEvent.mouseLocation
                    let newOrigin = NSPoint(
                        x: startOrigin.x + (currentMouse.x - startMouse.x),
                        y: startOrigin.y + (currentMouse.y - startMouse.y)
                    )
                    panel.setFrameOrigin(newOrigin)
                }
            case .leftMouseUp:
                dragStartMouseLocation = nil
                dragStartWindowOrigin = nil
                let nearest = self.nearestCorner(for: panel.frame)
                self.displaySettings.corner = nearest
                self.snapToCorner(nearest, animated: true)
            default:
                break
            }
            return event
        }
    }

    private func removeDragMonitor() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
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
        let size = Self.scaledSize(Self.baseCornerSize, for: displaySettings.size)
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
                ctx.duration = 0.22
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
