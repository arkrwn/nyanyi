import AppKit

final class MenuBarTicker {
    private weak var statusItem: NSStatusItem?
    private weak var statusButton: NSStatusBarButton?
    private var isActive = false
    private var currentRawText: String = ""
    private var marqueeOffset: Int = 0
    private var marqueeTimer: Timer?

    private let maxVisibleCharacters = 42

    init(statusItem: NSStatusItem, statusButton: NSStatusBarButton) {
        self.statusItem = statusItem
        self.statusButton = statusButton
    }

    func start() {
        isActive = true
        guard let button = statusButton else { return }
        statusItem?.length = NSStatusItem.variableLength
        let img = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Nyanyi"
        )
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        renderCurrentSlice()
    }

    func stop() {
        isActive = false
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        currentRawText = ""
        marqueeOffset = 0
    }

    func updateText(_ text: String) {
        guard isActive else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentRawText else { return }

        currentRawText = trimmed
        marqueeOffset = 0
        marqueeTimer?.invalidate()
        marqueeTimer = nil

        if trimmed.isEmpty {
            // Minimize menu bar ticker to compact music note icon when paused or idle
            guard let button = statusButton else { return }
            button.title = ""
            statusItem?.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            return
        }

        statusItem?.length = NSStatusItem.variableLength
        statusButton?.imagePosition = .imageLeading
        renderCurrentSlice()

        if trimmed.count > maxVisibleCharacters {
            marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
                self?.advanceMarquee()
            }
        }
    }

    private func advanceMarquee() {
        guard isActive, currentRawText.count > maxVisibleCharacters else { return }
        let padded = currentRawText + "   •   "
        marqueeOffset = (marqueeOffset + 1) % padded.count
        renderCurrentSlice()
    }

    private func renderCurrentSlice() {
        guard isActive, let button = statusButton else { return }

        let visibleString: String
        if currentRawText.count <= maxVisibleCharacters {
            visibleString = " " + currentRawText
        } else {
            let padded = Array(currentRawText + "   •   ")
            var slice: [Character] = []
            slice.reserveCapacity(maxVisibleCharacters)
            for i in 0..<maxVisibleCharacters {
                let idx = (marqueeOffset + i) % padded.count
                slice.append(padded[idx])
            }
            visibleString = " " + String(slice)
        }

        // Using native NSStatusBarButton title + font allows macOS to automatically invert
        // text color (white on dark menu bar, black on light menu bar) without ever overlapping!
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        button.title = visibleString
    }
}
