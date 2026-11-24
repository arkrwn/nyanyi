import Foundation
import Combine

struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double       // seconds (0 if unknown)
    let sourceName: String     // e.g. "Spotify", "YouTube Music (Chrome)", "YouTube Music (App)"
}

struct PlayerSnapshot {
    let track: TrackInfo
    let position: Double
    let isPlaying: Bool
}

final class PlayerMonitor: ObservableObject {
    @Published var currentTrack: TrackInfo?
    @Published var playerPosition: Double = 0
    @Published var isPlaying: Bool = false
    @Published var activeSourceName: String = ""

    var sourcePreference: PlayerSourcePreference = .auto

    private var pollTimer: Timer?
    private var interpolationTimer: Timer?
    private var lastKnownPosition: Double = 0
    private var lastPollTimestamp: Date = Date()
    private let pollQueue = DispatchQueue(label: "id.arkrwn.nyanyi.player-poll", qos: .utility)

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        // Poll active players every 1.0s on a background queue
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollPlayers()
        }
        // Interpolate position at ~4 Hz for responsive lyric highlighting
        interpolationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.interpolatePosition()
        }
        pollPlayers()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        interpolationTimer?.invalidate()
        interpolationTimer = nil
    }

    private func interpolatePosition() {
        guard isPlaying else { return }
        let elapsed = Date().timeIntervalSince(lastPollTimestamp)
        playerPosition = lastKnownPosition + elapsed
    }

    private func pollPlayers() {
        let preference = sourcePreference
        pollQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.resolveActiveSnapshot(preference: preference)

            DispatchQueue.main.async {
                guard let snap = snapshot else {
                    if self.isPlaying { self.isPlaying = false }
                    return
                }

                self.lastKnownPosition = snap.position
                self.lastPollTimestamp = Date()
                self.playerPosition = snap.position
                self.isPlaying = snap.isPlaying
                self.activeSourceName = snap.track.sourceName

                if self.currentTrack != snap.track {
                    self.currentTrack = snap.track
                }
            }
        }
    }

    private func resolveActiveSnapshot(preference: PlayerSourcePreference) -> PlayerSnapshot? {
        switch preference {
        case .spotify:
            return querySpotify()
        case .youtubeMusic:
            return queryYouTubeMusic()
        case .auto:
            let spotifySnap = querySpotify()
            if let s = spotifySnap, s.isPlaying {
                return s
            }
            let ytmSnap = queryYouTubeMusic()
            if let y = ytmSnap, y.isPlaying {
                return y
            }
            // If neither is actively playing, prefer whichever has a loaded paused track
            return spotifySnap ?? ytmSnap
        }
    }

    // MARK: - 1. Spotify (macOS Native AppleScript)

    private static let spotifyScriptSource = """
    if application "Spotify" is running then
        tell application "Spotify"
            set pState to player state as string
            if pState is "playing" or pState is "paused" then
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tDuration to duration of current track
                set pPos to player position
                return pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDuration as string) & "|||" & (pPos as string)
            else
                return "stopped"
            end if
        end tell
    else
        return "not_running"
    end if
    """

    private func querySpotify() -> PlayerSnapshot? {
        guard let raw = runAppleScript(Self.spotifyScriptSource),
              raw != "not_running", raw != "stopped" else {
            return nil
        }

        let parts = raw.components(separatedBy: "|||")
        guard parts.count == 6 else { return nil }

        let state = parts[0]
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let durationMs = Self.parseDouble(parts[4])
        let position = Self.parseDouble(parts[5])

        let track = TrackInfo(
            title: title,
            artist: artist,
            album: album,
            duration: durationMs / 1000.0,
            sourceName: "Spotify"
        )
        return PlayerSnapshot(
            track: track,
            position: position,
            isPlaying: state == "playing"
        )
    }

    // MARK: - 2. YouTube Music (Desktop Companion API + Browser Tabs)

    private func queryYouTubeMusic() -> PlayerSnapshot? {
        // First check YouTube Music Desktop App local companion server (if running on 127.0.0.1:26538 or 9863)
        if let desktopSnap = queryYouTubeMusicDesktopAPI() {
            return desktopSnap
        }
        // Check Chromium-family browsers and Safari for an open music.youtube.com tab
        let chromiumBrowsers = [
            "Google Chrome",
            "Arc",
            "Brave Browser",
            "Microsoft Edge",
            "Chromium",
            "Vivaldi"
        ]
        for browser in chromiumBrowsers {
            if let snap = queryChromiumYouTubeMusic(browserName: browser) {
                return snap
            }
        }
        if let safariSnap = querySafariYouTubeMusic() {
            return safariSnap
        }
        return nil
    }

    /// Queries th-ch/youtube-music or ytmdesktop local HTTP companion API if active.
    private func queryYouTubeMusicDesktopAPI() -> PlayerSnapshot? {
        guard let url = URL(string: "http://127.0.0.1:26538/api/v1/song-info") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.35

        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: PlayerSnapshot?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (json["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (json["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            let isPaused = (json["isPaused"] as? Bool) ?? false
            let elapsedSeconds = (json["elapsedSeconds"] as? Double)
                ?? Double(json["elapsedSeconds"] as? Int ?? 0)
            let songDuration = (json["songDuration"] as? Double)
                ?? Double(json["songDuration"] as? Int ?? 0)

            let track = TrackInfo(
                title: title,
                artist: artist,
                album: album,
                duration: songDuration,
                sourceName: "YouTube Music (App)"
            )
            snapshot = PlayerSnapshot(
                track: track,
                position: elapsedSeconds,
                isPlaying: !isPaused
            )
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.4)
        return snapshot
    }

    /// JS snippet executed inside a `music.youtube.com` tab to extract exact DOM title, artist, album, currentTime, duration, and paused state.
    private static let ytmExtractionJS: String = [
        "(function(){",
        "var v = document.querySelector('video');",
        "var tEl = document.querySelector('ytmusic-player-bar .title');",
        "var bEl = document.querySelector('ytmusic-player-bar .byline');",
        "var title = tEl ? tEl.textContent.trim() : '';",
        "var byline = bEl ? bEl.textContent.trim() : '';",
        "var parts = byline.split(/\\s*[•\\u2022\\u00b7]\\s*/);",
        "var artist = parts.length > 0 ? parts[0].trim() : '';",
        "var album = parts.length > 1 ? parts[1].trim() : '';",
        "if ((!title || !artist) && navigator.mediaSession && navigator.mediaSession.metadata) {",
        "  title = title || navigator.mediaSession.metadata.title || '';",
        "  artist = artist || navigator.mediaSession.metadata.artist || '';",
        "  album = album || navigator.mediaSession.metadata.album || '';",
        "}",
        "var pos = v ? (v.currentTime || 0) : 0;",
        "var dur = (v && v.duration && isFinite(v.duration)) ? v.duration : 0;",
        "var state = (v && !v.paused) ? 'playing' : 'paused';",
        "return state + '|||' + title + '|||' + artist + '|||' + album + '|||' + dur + '|||' + pos;",
        "})();"
    ].joined(separator: " ")

    private func queryChromiumYouTubeMusic(browserName: String) -> PlayerSnapshot? {
        let escapedJS = Self.ytmExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        if application "\(browserName)" is running then
            tell application "\(browserName)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then
                            set tabTitle to title of t
                            try
                                set jsRes to execute t javascript "\(escapedJS)"
                                return "JS|||" & jsRes & "|||" & tabTitle
                            on error
                                return "TITLE|||" & tabTitle
                            end try
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return "not_found"
        """

        guard let raw = runAppleScript(script), raw != "not_found" else {
            return nil
        }
        return parseYouTubeMusicAppleScriptResult(raw, sourceLabel: "YouTube Music (\(browserName))")
    }

    private func querySafariYouTubeMusic() -> PlayerSnapshot? {
        let escapedJS = Self.ytmExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        if application "Safari" is running then
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then
                            set tabTitle to name of t
                            try
                                set jsRes to do JavaScript "\(escapedJS)" in t
                                return "JS|||" & jsRes & "|||" & tabTitle
                            on error
                                return "TITLE|||" & tabTitle
                            end try
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return "not_found"
        """

        guard let raw = runAppleScript(script), raw != "not_found" else {
            return nil
        }
        return parseYouTubeMusicAppleScriptResult(raw, sourceLabel: "YouTube Music (Safari)")
    }

    private func parseYouTubeMusicAppleScriptResult(_ raw: String, sourceLabel: String) -> PlayerSnapshot? {
        if raw.hasPrefix("JS|||") {
            let payload = String(raw.dropFirst("JS|||".count))
            let parts = payload.components(separatedBy: "|||")
            if parts.count >= 6 {
                let state = parts[0]
                var title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                var artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let duration = Self.parseDouble(parts[4])
                let position = Self.parseDouble(parts[5])

                if title.isEmpty, parts.count >= 7 {
                    let fallback = Self.parseTabTitle(parts[6])
                    title = fallback.title
                    if artist.isEmpty { artist = fallback.artist }
                }

                guard !title.isEmpty else { return nil }

                let track = TrackInfo(
                    title: title,
                    artist: artist,
                    album: album,
                    duration: duration,
                    sourceName: sourceLabel
                )
                return PlayerSnapshot(
                    track: track,
                    position: position,
                    isPlaying: state == "playing"
                )
            }
        }

        if raw.hasPrefix("TITLE|||") {
            let tabTitle = String(raw.dropFirst("TITLE|||".count))
            let parsed = Self.parseTabTitle(tabTitle)
            guard !parsed.title.isEmpty else { return nil }

            // When browser Apple Events JS is not yet enabled, advance elapsed position smoothly for the same track
            let isSameTrack = (currentTrack?.title == parsed.title && currentTrack?.artist == parsed.artist)
            let estimatedPos = isSameTrack ? playerPosition : 0

            let track = TrackInfo(
                title: parsed.title,
                artist: parsed.artist,
                album: "",
                duration: 0,
                sourceName: sourceLabel
            )
            return PlayerSnapshot(
                track: track,
                position: estimatedPos,
                isPlaying: true
            )
        }

        return nil
    }

    /// Parses a browser tab title like `"Song Title - Artist Name - YouTube Music"` or `"▶ Song Title - Artist - YouTube Music"`.
    private static func parseTabTitle(_ rawTitle: String) -> (title: String, artist: String) {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("▶") || cleaned.hasPrefix("⏸") {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard cleaned != "YouTube Music" else { return ("", "") }

        if cleaned.hasSuffix(" - YouTube Music") {
            cleaned = String(cleaned.dropLast(" - YouTube Music".count))
        } else if cleaned.hasSuffix(" | YouTube Music") {
            cleaned = String(cleaned.dropLast(" | YouTube Music".count))
        }

        let segments = cleaned.components(separatedBy: " - ")
        if segments.count >= 2 {
            let title = segments[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = segments.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, artist)
        }
        return (cleaned, "")
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        guard let output = script?.executeAndReturnError(&error) else {
            return nil
        }
        return output.stringValue
    }

    private static func parseDouble(_ str: String) -> Double {
        let normalized = str.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }
}
