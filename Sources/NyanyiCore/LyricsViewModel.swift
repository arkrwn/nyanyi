import Foundation
import Combine

public final class LyricsViewModel: ObservableObject {
    @Published public var lines: [LyricLine] = []
    @Published public var currentLineIndex: Int?
    @Published public var lineProgress: Double = 0
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
                self?.updateActiveLine(for: position)
            }
            .store(in: &cancellables)

        playerMonitor.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        playerMonitor.$activeSourceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeSourceName)
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

            // If external databases (LRCLIB, NetEase, Lyrics.ovh) have no entry for this song
            // (for example local/indie YouTube Music tracks like "Josjis - Waru Leaf"),
            // extract synced captions or inline lyrics directly from the active Google Chrome tab!
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
