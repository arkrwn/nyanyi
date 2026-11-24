import Foundation
import Combine

public final class LyricsViewModel: ObservableObject {
    @Published public var lines: [LyricLine] = []
    @Published public var currentLineIndex: Int?
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

        trackTitle = track.title
        artist = track.artist
        activeSourceName = track.sourceName
        lines = []
        currentLineIndex = nil
        isLoading = true

        fetchTask = Task { @MainActor [weak self] in
            let fetched = await LyricsService.shared.fetchLyrics(track: track)
            guard !Task.isCancelled, let self = self else { return }
            self.lines = fetched
            self.isLoading = false
            self.updateActiveLine(for: self.playerMonitor.playerPosition)
        }
    }

    public func updateActiveLine(for position: Double) {
        guard !lines.isEmpty else {
            if currentLineIndex != nil { currentLineIndex = nil }
            return
        }

        var activeIndex: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= position + 0.15 {
                activeIndex = i
            } else {
                break
            }
        }

        if activeIndex != currentLineIndex {
            currentLineIndex = activeIndex
        }
    }
}
