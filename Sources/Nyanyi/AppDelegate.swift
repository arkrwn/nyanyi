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
    private var toggleItem: NSMenuItem!
    private var activeSourceItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlay()
        setupTicker()
        observeModeChanges()
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
        button.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Nyanyi"
        )
        button.title = ""
        statusItem.length = NSStatusItem.squareLength
    }

    private func setupOverlay() {
        overlayController = OverlayWindowController(
            viewModel: viewModel,
            displaySettings: displaySettings
        )
    }

    private func setupTicker() {
        guard let button = statusItem.button else { return }
        ticker = MenuBarTicker(statusButton: button)

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
        if title.isEmpty {
            ticker?.updateText("")
        } else if let idx = index, idx < lines.count {
            ticker?.updateText(lines[idx].text)
        } else if !lines.isEmpty {
            ticker?.updateText("\(title) - \(viewModel.artist)")
        } else {
            ticker?.updateText(title)
        }
    }

    private func observeModeChanges() {
        displaySettings.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.applyMode(mode)
            }
            .store(in: &cancellables)
    }

    private func observePlayerChanges() {
        viewModel.$activeSourceName
            .combineLatest(viewModel.$trackTitle)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceName, title in
                guard let self else { return }
                if title.isEmpty || sourceName.isEmpty {
                    self.activeSourceItem.title = "Auto-detecting Spotify / YouTube Music..."
                } else {
                    self.activeSourceItem.title = "Playing from \(sourceName): \(title)"
                }
            }
            .store(in: &cancellables)
    }

    private func applyMode(_ mode: DisplayMode) {
        for (m, item) in modeMenuItems {
            item.state = (m == mode) ? .on : .off
        }

        switch mode {
        case .floating, .corner, .subtitleBottom, .subtitleTop:
            ticker?.stop()
            setDefaultStatusIcon()
            overlayController.applyDisplayMode(mode)
            if isOverlayVisible {
                overlayController.showWindow(nil)
            }
            toggleItem.isHidden = false

        case .menuBar:
            overlayController.window?.orderOut(nil)
            toggleItem.isHidden = true
            statusItem.length = NSStatusItem.variableLength
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

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        isOverlayVisible.toggle()
        if isOverlayVisible {
            overlayController.showWindow(nil)
            sender.title = "Hide Overlay"
        } else {
            overlayController.window?.orderOut(nil)
            sender.title = "Show Overlay"
        }
    }
}
