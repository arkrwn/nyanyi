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

        // Active auto-detected player status
        activeSourceItem = NSMenuItem(
            title: "Auto-detecting Spotify / YouTube Music...",
            action: nil,
            keyEquivalent: ""
        )
        activeSourceItem.isEnabled = false
        menu.addItem(activeSourceItem)

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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines, index, title, isPlaying in
                guard let self, self.displaySettings.mode == .menuBar else { return }
                self.updateTickerText(lines: lines, index: index, title: title, isPlaying: isPlaying)
            }
            .store(in: &cancellables)
    }

    private func updateTickerText(lines: [LyricLine], index: Int?, title: String, isPlaying: Bool) {
        if title.isEmpty || !isPlaying {
            ticker?.updateText("")
        } else if let idx = index, idx < lines.count {
            ticker?.updateText(lines[idx].text)
        } else if !lines.isEmpty {
            ticker?.updateText("\(title) - \(viewModel.artist)")
        } else {
            ticker?.updateText(title)
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
    }

    private func observePlayerChanges() {
        viewModel.$activeSourceName
            .combineLatest(viewModel.$trackTitle, viewModel.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceName, title, isPlaying in
                guard let self else { return }
                if title.isEmpty || sourceName.isEmpty {
                    self.activeSourceItem.title = "Auto-detecting Spotify / YouTube Music..."
                } else if isPlaying {
                    self.activeSourceItem.title = "Playing from \(sourceName): \(title)"
                } else {
                    self.activeSourceItem.title = "Paused (\(sourceName)): \(title)"
                }
            }
            .store(in: &cancellables)
    }

    private func applyMode(_ mode: DisplayMode) {
        for (m, item) in modeMenuItems {
            item.state = (m == mode) ? .on : .off
        }

        switch mode {
        case .floating, .corner, .subtitle:
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

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        displaySettings.mode = mode
    }

    @objc private func selectOverlaySize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? OverlaySize else { return }
        displaySettings.size = size
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        isOverlayVisible.toggle()
        overlayController.isManuallyHidden = !isOverlayVisible
        sender.title = isOverlayVisible ? "Hide Overlay" : "Show Overlay"
    }
}
