import Foundation
import Combine

final class LyricsViewModel: ObservableObject {
    @Published var lines: [LyricLine] = []
    @Published var currentLineIndex: Int?
    @Published var trackTitle: String = ""
    @Published var artist: String = ""
    @Published var activeSourceName: String = ""
    @Published var isLoading: Bool = false
    @Published var isPlaying: Bool = false

    let playerMonitor = PlayerMonitor()
    let displaySettings = DisplaySettings()
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>?

    init() {
        playerMonitor.sourcePreference = displaySettings.sourcePreference

        displaySettings.$sourcePreference
            .removeDuplicates()
            .sink { [weak self] pref in
                self?.playerMonitor.sourcePreference = pref
            }
            .store(in: &cancellables)

        displaySettings.$phoneticMode
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                self.lines = self.lines.map { $0.withPhoneticMode(mode) }
            }
            .store(in: &cancellables)

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

        let phoneticMode = displaySettings.phoneticMode
        fetchTask = Task { [weak self] in
            let fetched = await LyricsService.shared.fetchLyrics(track: track, phoneticMode: phoneticMode)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self else { return }
                self.lines = fetched
                self.isLoading = false
                self.updateActiveLine(for: self.playerMonitor.playerPosition)
            }
        }
    }

    private func updateActiveLine(for position: Double) {
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
