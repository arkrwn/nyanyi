import AppKit
import Combine
import NyanyiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private let viewModel = LyricsViewModel()
    private var displaySettings: DisplaySettings { viewModel.displaySettings }
    private var isOverlayVisible = true
    private var ticker: MenuBarTicker?
    private var cancellables = Set<AnyCancellable>()
    private var modeMenuItems: [DisplayMode: NSMenuItem] = [:]
    private var sizeMenuItems: [OverlaySize: NSMenuItem] = [:]
    private var toggleItem: NSMenuItem!
    private var activeSourceItem: NSMenuItem!
    private var playPauseMenuItem: NSMenuItem!
    private var bottomNavbarAutoHideItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlay()
        setupTicker()
        observeSettingsChanges()
        observePlayerChanges()
        applyMode(displaySettings.mode)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setDefaultStatusIcon()

        let menu = NSMenu()

        // Active auto-detected player status + time
        activeSourceItem = NSMenuItem(
            title: "Auto-detecting Spotify / YouTube Music...",
            action: nil,
            keyEquivalent: ""
        )
        activeSourceItem.isEnabled = false
        menu.addItem(activeSourceItem)

        menu.addItem(NSMenuItem.separator())

        // Playback Controls directly in Menu Bar menu (useful in Menu Bar Ticker mode & all modes)
        playPauseMenuItem = NSMenuItem(
            title: "Play / Pause",
            action: #selector(menuTogglePlayPause(_:)),
            keyEquivalent: " "
        )
        playPauseMenuItem.target = self
        menu.addItem(playPauseMenuItem)

        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(menuNextTrack(_:)),
            keyEquivalent: "]"
        )
        nextItem.target = self
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(menuPreviousTrack(_:)),
            keyEquivalent: "["
        )
        prevItem.target = self
        menu.addItem(prevItem)

        menu.addItem(NSMenuItem.separator())

        // Display mode submenu
        let displayMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = (mode == displaySettings.mode) ? .on : .off
            displayMenu.addItem(item)
            modeMenuItems[mode] = item
        }
        displayMenu.addItem(NSMenuItem.separator())

        bottomNavbarAutoHideItem = NSMenuItem(
            title: "Bottom Navbar: Auto-Hide on Pause",
            action: #selector(toggleBottomNavbarAutoHide(_:)),
            keyEquivalent: ""
        )
        bottomNavbarAutoHideItem.target = self
        bottomNavbarAutoHideItem.state = displaySettings.bottomNavbarAutoHide ? .on : .off
        displayMenu.addItem(bottomNavbarAutoHideItem)

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Size submenu (Small, Medium, Large)
        let sizeMenu = NSMenu()
        for size in OverlaySize.allCases {
            let item = NSMenuItem(
                title: size.label,
                action: #selector(selectOverlaySize(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = size
            item.state = (size == displaySettings.size) ? .on : .off
            sizeMenu.addItem(item)
            sizeMenuItems[size] = item
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(NSMenuItem.separator())

        toggleItem = NSMenuItem(
            title: "Hide Overlay",
            action: #selector(toggleOverlay(_:)),
            keyEquivalent: "l"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Nyanyi",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setDefaultStatusIcon() {
        guard let button = statusItem.button else { return }
        statusItem.length = NSStatusItem.squareLength
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let img = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Nyanyi"
        )
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageOnly
    }

    private func setupOverlay() {
        overlayController = OverlayWindowController(
            viewModel: viewModel,
            displaySettings: displaySettings
        )
    }

    private func setupTicker() {
        guard let button = statusItem.button else { return }
        ticker = MenuBarTicker(statusItem: statusItem, statusButton: button)

        viewModel.$lines
            .combineLatest(viewModel.$currentLineIndex, viewModel.$trackTitle, viewModel.$isPlaying)
            .combineLatest(viewModel.$currentPosition)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] combined, _ in
                guard let self, self.displaySettings.mode == .menuBar else { return }
                let (lines, index, title, isPlaying) = combined
                self.updateTickerText(lines: lines, index: index, title: title, isPlaying: isPlaying)
            }
            .store(in: &cancellables)
    }

    private func updateTickerText(lines: [LyricLine], index: Int?, title: String, isPlaying: Bool) {
        if title.isEmpty || !isPlaying {
            ticker?.updateText("")
            return
        }
        let timeBadge = "[\(viewModel.formattedCurrentTime)]"
        if let idx = index, idx < lines.count {
            ticker?.updateText("\(timeBadge) \(lines[idx].text)")
        } else if !lines.isEmpty {
            ticker?.updateText("\(timeBadge) \(title) - \(viewModel.artist)")
        } else {
            ticker?.updateText("\(timeBadge) \(title)")
        }
    }

    private func observeSettingsChanges() {
        displaySettings.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.applyMode(mode)
            }
            .store(in: &cancellables)

        displaySettings.$size
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self else { return }
                for (s, item) in self.sizeMenuItems {
                    item.state = (s == size) ? .on : .off
                }
                self.overlayController.applyDisplayMode(self.displaySettings.mode)
            }
            .store(in: &cancellables)

        displaySettings.$bottomNavbarAutoHide
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.bottomNavbarAutoHideItem?.state = enabled ? .on : .off
                self.overlayController.updateVisibilityForPlayState()
            }
            .store(in: &cancellables)
    }

    private func observePlayerChanges() {
        viewModel.$activeSourceName
            .combineLatest(viewModel.$trackTitle, viewModel.$isPlaying, viewModel.$currentPosition)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceName, title, isPlaying, _ in
                guard let self else { return }
                self.playPauseMenuItem?.title = isPlaying ? "Pause" : "Play"
                if title.isEmpty || sourceName.isEmpty {
                    self.activeSourceItem.title = "Auto-detecting Spotify / YouTube Music..."
                } else {
                    let status = isPlaying ? "Playing" : "Paused"
                    self.activeSourceItem.title = "\(status) (\(sourceName)): \(title) [\(self.viewModel.formattedTimeDisplay)]"
                }
            }
            .store(in: &cancellables)
    }

    private func applyMode(_ mode: DisplayMode) {
        for (m, item) in modeMenuItems {
            item.state = (m == mode) ? .on : .off
        }

        switch mode {
        case .floating, .corner, .subtitle, .bottomNavbar:
            ticker?.stop()
            setDefaultStatusIcon()
            overlayController.applyDisplayMode(mode)
            overlayController.updateVisibilityForPlayState()
            toggleItem.isHidden = false

        case .menuBar:
            overlayController.window?.orderOut(nil)
            toggleItem.isHidden = true
            ticker?.start()
            updateTickerText(
                lines: viewModel.lines,
                index: viewModel.currentLineIndex,
                title: viewModel.trackTitle,
                isPlaying: viewModel.isPlaying
            )
        }
    }

    @objc private func menuTogglePlayPause(_ sender: NSMenuItem) {
        viewModel.togglePlayPause()
    }

    @objc private func menuNextTrack(_ sender: NSMenuItem) {
        viewModel.nextTrack()
    }

    @objc private func menuPreviousTrack(_ sender: NSMenuItem) {
        viewModel.previousTrack()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        displaySettings.mode = mode
    }

    @objc private func selectOverlaySize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? OverlaySize else { return }
        displaySettings.size = size
    }

    @objc private func toggleBottomNavbarAutoHide(_ sender: NSMenuItem) {
        displaySettings.bottomNavbarAutoHide.toggle()
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        isOverlayVisible.toggle()
        overlayController.isManuallyHidden = !isOverlayVisible
        sender.title = isOverlayVisible ? "Hide Overlay" : "Show Overlay"
    }
}
