import AppKit
import Combine

public struct TrackInfo: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double       // seconds (0 if unknown)
    public let sourceName: String     // e.g. "YouTube Music", "Spotify"

    public init(title: String, artist: String, album: String, duration: Double, sourceName: String) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.sourceName = sourceName
    }
}

public struct PlayerSnapshot: Equatable {
    public let track: TrackInfo
    public let position: Double
    public let isPlaying: Bool

    public init(track: TrackInfo, position: Double, isPlaying: Bool) {
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
    }
}

public final class PlayerMonitor: ObservableObject {
    @Published public var currentTrack: TrackInfo?
    @Published public var playerPosition: Double = 0
    @Published public var trackDuration: Double = 0
    @Published public var isPlaying: Bool = false
    @Published public var activeSourceName: String = ""
    @Published public var browserInlineLyrics: [LyricLine] = []

    private var pollTimer: Timer?
    private var interpolationTimer: Timer?
    private var lastKnownPosition: Double = 0
    private var lastPollTimestamp: Date = Date()
    private let pollQueue = DispatchQueue(label: "id.arkrwn.nyanyi.player-poll", qos: .utility)

    public init(autoStart: Bool = true) {
        if autoStart {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollPlayers()
        }
        interpolationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.interpolatePosition()
        }
        pollPlayers()
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        interpolationTimer?.invalidate()
        interpolationTimer = nil
    }

    private func interpolatePosition() {
        guard isPlaying else { return }
        let elapsed = Date().timeIntervalSince(lastPollTimestamp)
        // Cap interpolation to 0.55s so a paused/loading track never runs ahead of actual audio
        guard elapsed <= 0.55 else { return }
        playerPosition = lastKnownPosition + elapsed
    }

    // MARK: - Playback & Seek Controls (YouTube Music Chrome, Spotify Web Chrome, & Spotify.app)

    public func togglePlayPause() {
        let optimisticallyPlaying = !isPlaying
        isPlaying = optimisticallyPlaying
        lastPollTimestamp = Date()

        pollQueue.async { [weak self] in
            guard let self else { return }
            if self.isBundleRunning("com.google.Chrome") {
                let js = [
                    "(function(){",
                    "var yBtn = document.querySelector('ytmusic-player-bar #play-pause-button');",
                    "if (yBtn) { yBtn.click(); return 'ok'; }",
                    "var sBtn = document.querySelector('[data-testid=\"control-button-playpause\"]');",
                    "if (sBtn) { sBtn.click(); return 'ok'; }",
                    "var v = document.querySelector('video');",
                    "if (v) { if (v.paused) v.play(); else v.pause(); return 'ok'; }",
                    "return '';",
                    "})();"
                ].joined(separator: " ")
                if self.executeInChromeMusicTab(js: js) != nil {
                    self.pollPlayers()
                    return
                }
            }
            if self.isBundleRunning("com.spotify.client") {
                _ = self.runAppleScript("tell application \"Spotify\" to playpause")
                self.pollPlayers()
            }
        }
    }

    public func nextTrack() {
        pollQueue.async { [weak self] in
            guard let self else { return }
            if self.isBundleRunning("com.google.Chrome") {
                let js = [
                    "(function(){",
                    "var yNext = document.querySelector('ytmusic-player-bar .next-button');",
                    "if (yNext) { yNext.click(); return 'ok'; }",
                    "var sNext = document.querySelector('[data-testid=\"control-button-skip-forward\"]');",
                    "if (sNext) { sNext.click(); return 'ok'; }",
                    "return '';",
                    "})();"
                ].joined(separator: " ")
                if self.executeInChromeMusicTab(js: js) != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.pollPlayers() }
                    return
                }
            }
            if self.isBundleRunning("com.spotify.client") {
                _ = self.runAppleScript("tell application \"Spotify\" to next track")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.pollPlayers() }
            }
        }
    }

    public func previousTrack() {
        pollQueue.async { [weak self] in
            guard let self else { return }
            if self.isBundleRunning("com.google.Chrome") {
                let js = [
                    "(function(){",
                    "var yPrev = document.querySelector('ytmusic-player-bar .previous-button');",
                    "if (yPrev) { yPrev.click(); return 'ok'; }",
                    "var sPrev = document.querySelector('[data-testid=\"control-button-skip-back\"]');",
                    "if (sPrev) { sPrev.click(); return 'ok'; }",
                    "var v = document.querySelector('video');",
                    "if (v) { v.currentTime = 0; return 'ok'; }",
                    "return '';",
                    "})();"
                ].joined(separator: " ")
                if self.executeInChromeMusicTab(js: js) != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.pollPlayers() }
                    return
                }
            }
            if self.isBundleRunning("com.spotify.client") {
                _ = self.runAppleScript("tell application \"Spotify\" to previous track")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.pollPlayers() }
            }
        }
    }

    public func seek(to seconds: Double) {
        let maxDur = trackDuration > 0 ? trackDuration : max(seconds, 3600)
        let clamped = min(max(0, seconds), maxDur)
        lastKnownPosition = clamped
        lastPollTimestamp = Date()
        playerPosition = clamped

        pollQueue.async { [weak self] in
            guard let self else { return }
            let targetSec = String(format: "%.2f", clamped)
            if self.isBundleRunning("com.google.Chrome") {
                let js = [
                    "(function(){",
                    "var mp = document.getElementById('movie_player');",
                    "if (mp && typeof mp.seekTo === 'function') { mp.seekTo(\(targetSec), true); }",
                    "var v = document.querySelector('video');",
                    "if (v) { v.currentTime = \(targetSec); return 'ok'; }",
                    "var a = document.querySelector('audio');",
                    "if (a) { a.currentTime = \(targetSec); return 'ok'; }",
                    "return '';",
                    "})();"
                ].joined(separator: " ")
                if self.executeInChromeMusicTab(js: js) != nil {
                    return
                }
            }
            if self.isBundleRunning("com.spotify.client") {
                _ = self.runAppleScript("tell application \"Spotify\" to set player position to \(targetSec)")
            }
        }
    }

    public func seekBy(delta secondsDelta: Double) {
        seek(to: playerPosition + secondsDelta)
    }

    private func executeInChromeMusicTab(js: String) -> String? {
        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                set tabCount to count of tabs of w
                repeat with i from 1 to tabCount
                    set t to tab i of w
                    set tURL to URL of t
                    if tURL contains "music.youtube.com" or tURL contains "open.spotify.com" then
                        try
                            return execute t javascript "\(escapedJS)"
                        on error
                            return ""
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        guard let res = runAppleScript(script), !res.isEmpty else { return nil }
        return res
    }

    /// Queries the browser tab (Google Chrome) for inline lyrics or auto-captions/subtitles of the current track.
    public func fetchBrowserInlineLyrics() -> [LyricLine] {
        guard isBundleRunning("com.google.Chrome") else { return [] }
        let escapedJS = Self.browserLyricsExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                set tabCount to count of tabs of w
                repeat with i from 1 to tabCount
                    set t to tab i of w
                    set tURL to URL of t
                    if tURL contains "music.youtube.com" or tURL contains "open.spotify.com" then
                        try
                            return execute t javascript "\(escapedJS)"
                        on error
                            return ""
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        guard let raw = runAppleScript(script), !raw.isEmpty else { return [] }
        return Self.parseBrowserInlineLyricsOutput(raw, duration: currentTrack?.duration ?? 180)
    }

    private static let browserLyricsExtractionJS: String = [
        "(function(){",
        "try {",
        "  // 1. Check YouTube player caption track (timedtext json3) if available",
        "  var mp = document.getElementById('movie_player');",
        "  if (mp && mp.getPlayerResponse) {",
        "    var pr = mp.getPlayerResponse();",
        "    var tracks = pr && pr.captions && pr.captions.playerCaptionsTracklistRenderer && pr.captions.playerCaptionsTracklistRenderer.captionTracks;",
        "    if (tracks && tracks.length > 0) {",
        "      var cUrl = tracks[0].baseUrl + '&fmt=json3';",
        "      var xhr = new XMLHttpRequest();",
        "      xhr.open('GET', cUrl, false);",
        "      xhr.send(null);",
        "      if (xhr.status === 200 && xhr.responseText) {",
        "        var cj = JSON.parse(xhr.responseText);",
        "        if (cj && cj.events) {",
        "          var lrcOut = [];",
        "          for (var i = 0; i < cj.events.length; i++) {",
        "            var ev = cj.events[i];",
        "            if (!ev.segs) continue;",
        "            var txt = '';",
        "            for (var j = 0; j < ev.segs.length; j++) { txt += (ev.segs[j].utf8 || ''); }",
        "            txt = txt.replace(/\\n+/g, ' ').trim();",
        "            if (txt) {",
        "              var sec = (ev.tStartMs || 0) / 1000.0;",
        "              lrcOut.push(sec.toFixed(2) + ':::' + txt);",
        "            }",
        "          }",
        "          if (lrcOut.length > 0) return 'SYNCED|||' + lrcOut.join('\\n');",
        "        }",
        "      }",
        "    }",
        "  }",
        "  // 2. Check YouTube Music built-in Lyrics tab DOM if rendered",
        "  var ytmLyrics = document.querySelector('ytmusic-description-shelf-renderer .description');",
        "  if (ytmLyrics && ytmLyrics.textContent && ytmLyrics.textContent.trim().length > 20) {",
        "    return 'PLAIN|||' + ytmLyrics.textContent.trim();",
        "  }",
        "  // 3. Check Spotify Web Player lyrics lines if rendered",
        "  var spLines = document.querySelectorAll('[data-testid=\"fullscreen-lyric\"]');",
        "  if (spLines && spLines.length > 2) {",
        "    var arr = [];",
        "    spLines.forEach(function(e){ var t = (e.textContent || '').trim(); if (t) arr.push(t); });",
        "    if (arr.length > 0) return 'PLAIN|||' + arr.join('\\n');",
        "  }",
        "} catch(e) {}",
        "return '';",
        "})();"
    ].joined(separator: " ")

    public static func parseBrowserInlineLyricsOutput(_ raw: String, duration: Double) -> [LyricLine] {
        if raw.hasPrefix("SYNCED|||") {
            let body = String(raw.dropFirst("SYNCED|||".count))
            var lines: [LyricLine] = []
            for row in body.components(separatedBy: .newlines) {
                let parts = row.components(separatedBy: ":::")
                guard parts.count == 2,
                      let time = Double(parts[0]) else { continue }
                let text = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    lines.append(LyricLine(time: time, text: text))
                }
            }
            return lines.sorted { $0.time < $1.time }
        }
        if raw.hasPrefix("PLAIN|||") {
            let body = String(raw.dropFirst("PLAIN|||".count))
            return LyricsService.parsePlainLyrics(body, duration: duration)
        }
        return []
    }

    private func pollPlayers() {
        pollQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.resolveActiveSnapshot()

            DispatchQueue.main.async {
                guard let snap = snapshot else {
                    if self.isPlaying { self.isPlaying = false }
                    return
                }

                let titleOrArtistChanged = (self.currentTrack?.title != snap.track.title || self.currentTrack?.artist != snap.track.artist)
                if self.currentTrack != snap.track {
                    self.currentTrack = snap.track
                }
                if snap.track.duration > 0 {
                    self.trackDuration = snap.track.duration
                } else if titleOrArtistChanged {
                    self.trackDuration = 0
                }

                if titleOrArtistChanged {
                    let initialPos = max(0, snap.position)
                    self.lastKnownPosition = initialPos
                    self.lastPollTimestamp = Date()
                    self.playerPosition = initialPos
                } else if snap.position >= 0 {
                    self.lastKnownPosition = snap.position
                    self.lastPollTimestamp = Date()
                    self.playerPosition = snap.position
                }

                self.isPlaying = snap.isPlaying
                self.activeSourceName = snap.track.sourceName
            }
        }
    }

    /// Checks running apps ONLY via NSWorkspace (never triggers "Where is <App>?" popup)
    private func isBundleRunning(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
    }

    private func resolveActiveSnapshot() -> PlayerSnapshot? {
        // 1. Check Google Chrome tabs first (supports both YouTube Music web and Spotify Web Player)
        if isBundleRunning("com.google.Chrome"),
           let chromeSnap = queryChromiumMusicTabs(appName: "Google Chrome") {
            if chromeSnap.isPlaying { return chromeSnap }
            if let spotifyAppSnap = querySpotifyApp(), spotifyAppSnap.isPlaying {
                return spotifyAppSnap
            }
            return chromeSnap
        }

        // 2. Check native Spotify.app ONLY if com.spotify.client is running
        if let spotifySnap = querySpotifyApp() {
            return spotifySnap
        }

        return nil
    }

    // MARK: - 1. Browser Tabs: YouTube Music (music.youtube.com) & Spotify Web (open.spotify.com)

    /// JavaScript executed inside a `music.youtube.com` tab to extract exact current song title, artist, album, currentTime, duration, and paused state from DOM + MediaSession.
    private static let ytmExtractionJS: String = [
        "(function(){",
        "var v = document.querySelector('video');",
        "var tEl = document.querySelector('ytmusic-player-bar .title');",
        "var bEl = document.querySelector('ytmusic-player-bar .byline');",
        "var title = tEl ? (tEl.textContent || tEl.getAttribute('title') || '').trim() : '';",
        "var artist = ''; var album = '';",
        "if (bEl) {",
        "  var aLinks = bEl.querySelectorAll('a');",
        "  for (var i = 0; i < aLinks.length; i++) {",
        "    var href = aLinks[i].getAttribute('href') || '';",
        "    var txt = (aLinks[i].textContent || '').trim();",
        "    if (!txt) continue;",
        "    if (!artist && (href.indexOf('channel/') !== -1 || i === 0)) artist = txt;",
        "    else if (!album && (href.indexOf('browse/MPRE') !== -1 || href.indexOf('browse/FEmusic') !== -1)) album = txt;",
        "  }",
        "  if (!artist) {",
        "    var byline = (bEl.textContent || bEl.getAttribute('title') || '').trim();",
        "    var parts = byline.split(/\\s*[•\\u2022\\u00b7]\\s*/);",
        "    artist = parts.length > 0 ? parts[0].trim() : '';",
        "    if (!album && parts.length > 1) album = parts[1].trim();",
        "  }",
        "}",
        "if (navigator.mediaSession && navigator.mediaSession.metadata) {",
        "  if (!title) title = (navigator.mediaSession.metadata.title || '').trim();",
        "  if (!artist) artist = (navigator.mediaSession.metadata.artist || '').trim();",
        "  if (!album) album = (navigator.mediaSession.metadata.album || '').trim();",
        "}",
        "var timeInfo = document.querySelector('ytmusic-player-bar .time-info');",
        "var pos = 0; var dur = 0;",
        "if (timeInfo) {",
        "  var tp = (timeInfo.textContent || '').trim().split(/\\s*\\/\\s*/);",
        "  function pSec(s){ if(!s)return 0; var a=s.trim().split(':').map(Number); return a.length===2 ? a[0]*60+a[1] : (a.length===3 ? a[0]*3600+a[1]*60+a[2] : 0); }",
        "  if (tp[0]) pos = pSec(tp[0]);",
        "  if (tp[1]) dur = pSec(tp[1]);",
        "}",
        "if (v && typeof v.currentTime === 'number' && !isNaN(v.currentTime)) {",
        "  if (pos === 0 || Math.abs(v.currentTime - pos) < 2.0) pos = v.currentTime;",
        "}",
        "if (!dur && v && typeof v.duration === 'number' && isFinite(v.duration) && v.duration > 0) {",
        "  dur = v.duration;",
        "}",
        "var isBuffering = v ? (v.readyState < 2 || v.seeking) : false;",
        "var playPauseBtn = document.querySelector('ytmusic-player-bar #play-pause-button');",
        "var btnTitle = playPauseBtn ? ((playPauseBtn.getAttribute('title') || playPauseBtn.getAttribute('aria-label') || '').toLowerCase()) : '';",
        "var btnSaysPlaying = (btnTitle.indexOf('pause') !== -1 || btnTitle.indexOf('jeda') !== -1);",
        "var btnSaysPaused = (btnTitle.indexOf('play') !== -1 || btnTitle.indexOf('putar') !== -1);",
        "var videoPlaying = (v && !v.paused && !v.ended && !isBuffering);",
        "var state = (videoPlaying && !btnSaysPaused) || (btnSaysPlaying && !v) ? 'playing' : 'paused';",
        "return state + '|||' + title + '|||' + artist + '|||' + album + '|||' + dur + '|||' + pos;",
        "})();"
    ].joined(separator: " ")

    /// JavaScript executed inside an `open.spotify.com` tab to extract current song title, artist, currentTime, duration, and playing state from Spotify Web Player DOM + MediaSession.
    private static let spotifyWebExtractionJS: String = [
        "(function(){",
        "var tEl = document.querySelector('[data-testid=\"context-item-info-title\"]') || document.querySelector('[data-testid=\"now-playing-widget\"] a[href*=\"/track/\"], [data-testid=\"now-playing-widget\"] a[href*=\"/album/\"]');",
        "var aEls = document.querySelectorAll('[data-testid=\"context-item-info-subtitles\"] a, [data-testid=\"context-item-info-artist\"]');",
        "var title = tEl ? (tEl.textContent || '').trim() : '';",
        "var artists = []; aEls.forEach(function(e){ if(e.textContent) artists.push(e.textContent.trim()); });",
        "var artist = artists.join(', ');",
        "var album = '';",
        "if (navigator.mediaSession && navigator.mediaSession.metadata) {",
        "  title = title || navigator.mediaSession.metadata.title || '';",
        "  artist = artist || navigator.mediaSession.metadata.artist || '';",
        "  album = album || navigator.mediaSession.metadata.album || '';",
        "}",
        "function pSec(s){ if(!s)return 0; var a=s.trim().split(':').map(Number); return a.length===2 ? a[0]*60+a[1] : (a.length===3 ? a[0]*3600+a[1]*60+a[2] : 0); }",
        "var posEl = document.querySelector('[data-testid=\"playback-position\"]');",
        "var durEl = document.querySelector('[data-testid=\"playback-duration\"]');",
        "var pos = posEl ? pSec(posEl.textContent) : 0;",
        "var dur = durEl ? pSec(durEl.textContent) : 0;",
        "var playBtn = document.querySelector('[data-testid=\"control-button-playpause\"]');",
        "var aria = playBtn ? (playBtn.getAttribute('aria-label') || '').toLowerCase() : '';",
        "var state = (aria.indexOf('pause') !== -1 || aria.indexOf('jeda') !== -1) ? 'playing' : 'paused';",
        "if (!playBtn && navigator.mediaSession && navigator.mediaSession.playbackState === 'playing') state = 'playing';",
        "return state + '|||' + title + '|||' + artist + '|||' + album + '|||' + dur + '|||' + pos;",
        "})();"
    ].joined(separator: " ")

    private func queryChromiumMusicTabs(appName: String) -> PlayerSnapshot? {
        let escapedYTMJS = Self.ytmExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSpotifyJS = Self.spotifyWebExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Important: inside `repeat with t in tabs of w`, use `title of t` (never `name of t` which resolves to window name!)
        let script = """
        tell application "\(appName)"
            repeat with w in windows
                set tabCount to count of tabs of w
                repeat with i from 1 to tabCount
                    set t to tab i of w
                    set tURL to URL of t
                    if tURL contains "music.youtube.com" then
                        set tTitle to title of t
                        try
                            set jsRes to execute t javascript "\(escapedYTMJS)"
                            return "YTM_JS|||" & jsRes & "|||" & tTitle
                        on error
                            return "YTM_TITLE|||" & tTitle
                        end try
                    else if tURL contains "open.spotify.com" then
                        set tTitle to title of t
                        try
                            set jsRes to execute t javascript "\(escapedSpotifyJS)"
                            return "SPOTIFY_JS|||" & jsRes & "|||" & tTitle
                        on error
                            return "SPOTIFY_TITLE|||" & tTitle
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return "not_found"
        """

        guard let raw = runAppleScript(script), raw != "not_found" else {
            return nil
        }
        return parseBrowserMusicResult(raw)
    }

    private func querySafariMusicTabs() -> PlayerSnapshot? {
        let escapedYTMJS = Self.ytmExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSpotifyJS = Self.spotifyWebExtractionJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Safari"
            repeat with w in windows
                set tabCount to count of tabs of w
                repeat with i from 1 to tabCount
                    set t to tab i of w
                    set tURL to URL of t
                    if tURL contains "music.youtube.com" then
                        set tTitle to name of t
                        try
                            set jsRes to do JavaScript "\(escapedYTMJS)" in t
                            return "YTM_JS|||" & jsRes & "|||" & tTitle
                        on error
                            return "YTM_TITLE|||" & tTitle
                        end try
                    else if tURL contains "open.spotify.com" then
                        set tTitle to name of t
                        try
                            set jsRes to do JavaScript "\(escapedSpotifyJS)" in t
                            return "SPOTIFY_JS|||" & jsRes & "|||" & tTitle
                        on error
                            return "SPOTIFY_TITLE|||" & tTitle
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return "not_found"
        """

        guard let raw = runAppleScript(script), raw != "not_found" else {
            return nil
        }
        return parseBrowserMusicResult(raw)
    }

    public func parseBrowserMusicResult(_ raw: String) -> PlayerSnapshot? {
        if raw.hasPrefix("YTM_JS|||") {
            let payload = String(raw.dropFirst("YTM_JS|||".count))
            return parseJSResultPayload(payload, sourceLabel: "YouTube Music", isSpotifyWeb: false)
        }
        if raw.hasPrefix("SPOTIFY_JS|||") {
            let payload = String(raw.dropFirst("SPOTIFY_JS|||".count))
            return parseJSResultPayload(payload, sourceLabel: "Spotify Web", isSpotifyWeb: true)
        }
        if raw.hasPrefix("YTM_TITLE|||") {
            let tabTitle = String(raw.dropFirst("YTM_TITLE|||".count))
            let parsed = Self.parseTabTitle(tabTitle)
            guard !parsed.title.isEmpty else { return nil }
            let track = TrackInfo(
                title: parsed.title,
                artist: parsed.artist,
                album: "",
                duration: 0,
                sourceName: "YouTube Music"
            )
            return PlayerSnapshot(track: track, position: -1, isPlaying: true)
        }
        if raw.hasPrefix("SPOTIFY_TITLE|||") {
            let tabTitle = String(raw.dropFirst("SPOTIFY_TITLE|||".count))
            let parsed = Self.parseSpotifyWebTabTitle(tabTitle)
            guard !parsed.title.isEmpty else { return nil }
            let track = TrackInfo(
                title: parsed.title,
                artist: parsed.artist,
                album: "",
                duration: 0,
                sourceName: "Spotify Web"
            )
            return PlayerSnapshot(track: track, position: -1, isPlaying: true)
        }
        // Backwards compatibility with legacy test prefixes
        if raw.hasPrefix("JS|||") {
            let payload = String(raw.dropFirst("JS|||".count))
            return parseJSResultPayload(payload, sourceLabel: "YouTube Music (Google Chrome)", isSpotifyWeb: false)
        }
        if raw.hasPrefix("TITLE|||") {
            let tabTitle = String(raw.dropFirst("TITLE|||".count))
            let parsed = Self.parseTabTitle(tabTitle)
            guard !parsed.title.isEmpty else { return nil }
            let track = TrackInfo(
                title: parsed.title,
                artist: parsed.artist,
                album: "",
                duration: 0,
                sourceName: "YouTube Music"
            )
            return PlayerSnapshot(track: track, position: 0, isPlaying: true)
        }
        return nil
    }

    public func parseYouTubeMusicAppleScriptResult(_ raw: String, sourceLabel: String) -> PlayerSnapshot? {
        if raw.hasPrefix("JS|||") {
            let payload = String(raw.dropFirst("JS|||".count))
            return parseJSResultPayload(payload, sourceLabel: sourceLabel, isSpotifyWeb: false)
        }
        return parseBrowserMusicResult(raw)
    }

    private func parseJSResultPayload(_ payload: String, sourceLabel: String, isSpotifyWeb: Bool) -> PlayerSnapshot? {
        let parts = payload.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let state = parts[0]
        var title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        var artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Self.parseDouble(parts[4])
        let position = Self.parseDouble(parts[5])

        if title.isEmpty, parts.count >= 7 {
            let fallback = isSpotifyWeb ? Self.parseSpotifyWebTabTitle(parts[6]) : Self.parseTabTitle(parts[6])
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

    /// Parses a YouTube Music tab title like `"Song Title - Artist Name - YouTube Music"` or `"▶ Song Title • Artist - YouTube Music"`.
    public static func parseTabTitle(_ rawTitle: String) -> (title: String, artist: String) {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = cleaned.first, first == "▶" || first == "⏸" || first == "🔊" {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Ignore generic home/unplaying tab titles or non-YTM tab titles
        let lower = cleaned.lowercased()
        if cleaned.isEmpty || lower == "youtube music" || lower == "youtube" {
            return ("", "")
        }

        // Only accept tab titles that actually belong to YouTube Music (or already had the suffix)
        if cleaned.hasSuffix(" - YouTube Music") {
            cleaned = String(cleaned.dropLast(" - YouTube Music".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.hasSuffix(" | YouTube Music") {
            cleaned = String(cleaned.dropLast(" | YouTube Music".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.isEmpty || cleaned.lowercased() == "youtube music" {
            return ("", "")
        }

        // Check bullet separator (`Song • Artist`) or dash separator (`Song - Artist`)
        let bulletSegments = cleaned.components(separatedBy: " • ")
        if bulletSegments.count >= 2 {
            let title = bulletSegments[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = bulletSegments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, artist)
        }

        let dashSegments = cleaned.components(separatedBy: " - ")
        if dashSegments.count >= 2 {
            let title = dashSegments[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = dashSegments.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, artist)
        }

        return (cleaned, "")
    }

    /// Parses a Spotify Web Player tab title like `"Song Title • Artist Name"`, `"Song Title - song and lyrics by Artist | Spotify"`, or `"Spotify – Web Player"`.
    public static func parseSpotifyWebTabTitle(_ rawTitle: String) -> (title: String, artist: String) {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = cleaned.first, first == "▶" || first == "⏸" || first == "🔊" {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lower = cleaned.lowercased()
        if cleaned.isEmpty
            || lower.hasPrefix("spotify - web player")
            || lower.hasPrefix("spotify – web player")
            || lower == "spotify" {
            return ("", "")
        }

        if cleaned.hasSuffix(" | Spotify") {
            cleaned = String(cleaned.dropLast(" | Spotify".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.hasSuffix(" - Spotify") {
            cleaned = String(cleaned.dropLast(" - Spotify".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Format: "Song • Artist"
        let bulletParts = cleaned.components(separatedBy: " • ")
        if bulletParts.count >= 2 {
            return (
                bulletParts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                bulletParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Format: "Song - song and lyrics by Artist"
        if let byRange = cleaned.range(of: " - song and lyrics by ", options: .caseInsensitive) {
            let title = String(cleaned[..<byRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = String(cleaned[byRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, artist)
        }

        let dashParts = cleaned.components(separatedBy: " - ")
        if dashParts.count >= 2 {
            return (
                dashParts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                dashParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return (cleaned, "")
    }

    // MARK: - 2. Native Spotify.app (Checked ONLY when com.spotify.client is running)

    private static let spotifyScriptSource = """
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
    """

    private func querySpotifyApp() -> PlayerSnapshot? {
        guard isBundleRunning("com.spotify.client"),
              let raw = runAppleScript(Self.spotifyScriptSource) else {
            return nil
        }
        return Self.parseSpotifyAppleScriptResult(raw)
    }

    public static func parseSpotifyAppleScriptResult(_ raw: String) -> PlayerSnapshot? {
        guard raw != "not_running", raw != "stopped" else { return nil }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count == 6 else { return nil }

        let state = parts[0]
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let durationMs = parseDouble(parts[4])
        let position = parseDouble(parts[5])

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

    // MARK: - 3. Optional YouTube Music Desktop Companion API

    private func queryYouTubeMusicDesktopAPI() -> PlayerSnapshot? {
        guard let url = URL(string: "http://127.0.0.1:26538/api/v1/song-info") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.25

        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: PlayerSnapshot?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data else {
                return
            }
            snapshot = Self.parseYouTubeMusicDesktopJSON(data)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.3)
        return snapshot
    }

    public static func parseYouTubeMusicDesktopJSON(_ data: Data) -> PlayerSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (json["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (json["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

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
        return PlayerSnapshot(
            track: track,
            position: elapsedSeconds,
            isPlaying: !isPaused
        )
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        guard let output = script?.executeAndReturnError(&error) else {
            return nil
        }
        return output.stringValue
    }

    public static func parseDouble(_ str: String) -> Double {
        let normalized = str.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }
}
