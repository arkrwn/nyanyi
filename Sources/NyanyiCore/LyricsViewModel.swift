import Foundation
import Combine

public final class LyricsViewModel: ObservableObject {
    @Published public var lines: [LyricLine] = []
    @Published public var currentLineIndex: Int?
    @Published public var lineProgress: Double = 0
    @Published public var currentPosition: Double = 0
    @Published public var trackDuration: Double = 0
    @Published public var trackTitle: String = ""
    @Published public var artist: String = ""
    @Published public var activeSourceName: String = ""
    @Published public var isLoading: Bool = false
    @Published public var isPlaying: Bool = false
    @Published public var isHovering: Bool = false

    public let playerMonitor = PlayerMonitor()
    public let displaySettings = DisplaySettings()
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>?

    public init() {
        playerMonitor.$currentTrack
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.onTrackChanged(track)
            }
            .store(in: &cancellables)

        playerMonitor.$playerPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                guard let self else { return }
                self.currentPosition = position
                self.updateActiveLine(for: position)
            }
            .store(in: &cancellables)

        playerMonitor.$trackDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$trackDuration)

        playerMonitor.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        playerMonitor.$activeSourceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeSourceName)
    }

    // MARK: - Playback Controls & Seek

    public func togglePlayPause() {
        playerMonitor.togglePlayPause()
    }

    public func nextTrack() {
        playerMonitor.nextTrack()
    }

    public func previousTrack() {
        playerMonitor.previousTrack()
    }

    public func seek(to seconds: Double) {
        playerMonitor.seek(to: seconds)
        currentPosition = max(0, seconds)
        updateActiveLine(for: currentPosition)
    }

    public func seekBy(delta secondsDelta: Double) {
        seek(to: currentPosition + secondsDelta)
    }

    /// Steps forward (`+1`) or backward (`-1`) by lyric lines (or by 3.5 seconds if no synced lines)
    /// and seeks the active player (YouTube Music / Spotify) accordingly.
    public func stepLyricLine(direction: Int) {
        guard !lines.isEmpty else {
            seekBy(delta: Double(direction) * 3.5)
            return
        }
        let currentIdx = currentLineIndex ?? 0
        let targetIdx = min(max(0, currentIdx + direction), lines.count - 1)
        let targetTime = max(0, lines[targetIdx].time + 0.05)
        seek(to: targetTime)
    }

    public var formattedCurrentTime: String {
        Self.formatTime(currentPosition)
    }

    public var formattedDuration: String {
        let effectiveDur = effectiveTrackDuration
        return effectiveDur > 0 ? Self.formatTime(effectiveDur) : "--:--"
    }

    public var formattedTimeDisplay: String {
        "\(formattedCurrentTime) / \(formattedDuration)"
    }

    public var effectiveTrackDuration: Double {
        if trackDuration > 0 { return trackDuration }
        if let lastLine = lines.last { return max(currentPosition, lastLine.time + 8.0) }
        return max(currentPosition, 0)
    }

    public var trackProgressFraction: Double {
        let dur = effectiveTrackDuration
        guard dur > 0 else { return 0 }
        return min(max(currentPosition / dur, 0.0), 1.0)
    }

    public static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(floor(seconds))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func onTrackChanged(_ track: TrackInfo?) {
        fetchTask?.cancel()

        guard let track = track else {
            lines = []
            currentLineIndex = nil
            trackTitle = ""
            artist = ""
            activeSourceName = ""
            isLoading = false
            return
        }

        let isSameSong = (trackTitle == track.title && artist == track.artist && !trackTitle.isEmpty)
        activeSourceName = track.sourceName
        if track.duration > 0 {
            trackDuration = track.duration
        }

        if !isSameSong {
            trackTitle = track.title
            artist = track.artist
            lines = []
            currentLineIndex = nil
            isLoading = true
        } else if !lines.isEmpty && track.duration <= 0 {
            return
        }

        fetchTask = Task { @MainActor [weak self] in
            var fetched = await LyricsService.shared.fetchLyrics(track: track)
            guard !Task.isCancelled, let self = self else { return }

            if fetched.isEmpty {
                let inline = self.playerMonitor.fetchBrowserInlineLyrics()
                if !inline.isEmpty {
                    fetched = inline
                }
            }

            if !fetched.isEmpty || self.lines.isEmpty {
                self.lines = fetched
            }
            self.isLoading = false
            self.updateActiveLine(for: self.playerMonitor.playerPosition)
        }
    }

    public func updateActiveLine(for position: Double) {
        guard !lines.isEmpty else {
            if currentLineIndex != nil { currentLineIndex = nil }
            if lineProgress != 0 { lineProgress = 0 }
            return
        }

        var activeIndex: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= position + 0.03 {
                activeIndex = i
            } else {
                break
            }
        }

        if activeIndex != currentLineIndex {
            currentLineIndex = activeIndex
        }

        if let idx = activeIndex {
            let startTime = lines[idx].time
            let endTime: Double
            if idx + 1 < lines.count {
                endTime = max(startTime + 0.5, lines[idx + 1].time)
            } else {
                endTime = startTime + 4.0
            }
            let rawProgress = (position - startTime) / (endTime - startTime)
            lineProgress = min(max(rawProgress, 0.0), 1.0)
        } else {
            lineProgress = 0
        }
    }
}
