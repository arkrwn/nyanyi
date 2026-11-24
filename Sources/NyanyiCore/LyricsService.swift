import Foundation

public struct LyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let time: Double
    public let text: String
    public let isInstrumental: Bool
    public let annotations: [AnnotatedChar]
    public let hasPhonetics: Bool

    public static let instrumentalLabel = "♪ Music Only ♪"

    public init(time: Double, text: String, isInstrumental: Bool = false) {
        self.time = time
        self.text = text
        self.isInstrumental = isInstrumental
        if isInstrumental {
            self.annotations = []
            self.hasPhonetics = false
        } else {
            let chars = PhoneticConverter.annotate(text)
            self.annotations = chars
            self.hasPhonetics = chars.contains { !$0.phonetic.isEmpty }
        }
    }

    public static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time == rhs.time && lhs.text == rhs.text && lhs.isInstrumental == rhs.isInstrumental && lhs.hasPhonetics == rhs.hasPhonetics
    }
}

public struct LRCLibResponse: Decodable {
    public let id: Int?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?
}

public final class LyricsService {
    public static let shared = LyricsService()

    private let baseURL = "https://lrclib.net/api"
    private let session: URLSession
    private var cache: [String: [LyricLine]] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Nyanyi/1.0 (https://github.com/arkrwn/nyanyi)"
        ]
        session = URLSession(configuration: config)
    }

    public func fetchLyrics(track: TrackInfo) async -> [LyricLine] {
        let cleanedTitle = Self.cleanTrackTitle(track.title)
        let cleanedArtist = Self.cleanArtistName(track.artist)
        let cleanedAlbum = Self.cleanAlbumName(track.album)
        let durationBucket = track.duration > 5 ? Int(round(track.duration)) : 0
        let cacheKey = "\(cleanedArtist.lowercased())|\(cleanedTitle.lowercased())|\(durationBucket)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let cleanedTrack = TrackInfo(
            title: cleanedTitle,
            artist: cleanedArtist,
            album: cleanedAlbum,
            duration: track.duration,
            sourceName: track.sourceName
        )

        // 1. Primary: Search LRCLIB and score all candidates by synced LRC availability, exact title, exact artist, and closest duration
        if let lines = await fetchSearch(title: cleanedTitle, artist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 2. Try LRCLIB exact /get endpoint with cleaned metadata (without noisy YouTube view-count album)
        if let lines = await fetchExact(track: cleanedTrack, requireSynced: true), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 3. Fallback search by cleaned title only (scored against expected artist + duration)
        if let lines = await fetchSearch(title: cleanedTitle, artist: "", expectedArtist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 4. Free-textLRCLIB `?q=` query (catches remixes, regional spelling variations, or reversed artist/title)
        if let lines = await fetchFreeQuerySearch(query: "\(cleanedTitle) \(cleanedArtist)", expectedTitle: cleanedTitle, expectedArtist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 5. Secondary provider: NetEase Cloud Music synced LRC lookup (great coverage for Asian, K-Pop, J-Pop, Indonesian, and global tracks)
        if let lines = await fetchNetEaseSyncedLRC(title: cleanedTitle, artist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 6. Tertiary provider: Lyrics.ovh REST API (`https://api.lyrics.ovh/v1/{artist}/{title}`)
        if let lines = await fetchLyricsOvh(title: cleanedTitle, artist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        // 7. Final fallback: unsynced plainLyrics from LRCLIB exact match if no synced LRC existed anywhere
        if let lines = await fetchExact(track: cleanedTrack, requireSynced: false), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        return []
    }

    private func fetchExact(track: TrackInfo, requireSynced: Bool) async -> [LyricLine]? {
        var components = URLComponents(string: "\(baseURL)/get")
        var queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if !track.album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(track.duration))))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let result = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            if let lrc = result.syncedLyrics, !lrc.isEmpty {
                return Self.parseLRC(lrc, targetDuration: track.duration, candidateDuration: result.duration ?? 0)
            }
            if !requireSynced, let plain = result.plainLyrics, !plain.isEmpty {
                let dur = track.duration > 5 ? track.duration : (result.duration ?? track.duration)
                return Self.parsePlainLyrics(plain, duration: dur)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchSearch(title: String, artist: String, expectedArtist: String? = nil, duration: Double) async -> [LyricLine]? {
        var components = URLComponents(string: "\(baseURL)/search")
        var queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
            let targetArtist = (expectedArtist ?? artist).lowercased()
            let targetTitle = title.lowercased()

            let scored = results.sorted { a, b in
                Self.scoreCandidate(a, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration) >
                Self.scoreCandidate(b, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration)
            }

            if let bestSynced = scored.first(where: {
                ($0.syncedLyrics ?? "").isEmpty == false &&
                Self.scoreCandidate($0, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration) >= 110
            }), let lrc = bestSynced.syncedLyrics {
                return Self.parseLRC(lrc, targetDuration: duration, candidateDuration: bestSynced.duration ?? 0)
            }
            if let bestPlain = scored.first(where: {
                ($0.plainLyrics ?? "").isEmpty == false &&
                Self.scoreCandidate($0, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration) >= 40
            }), let plain = bestPlain.plainLyrics {
                let dur = duration > 5 ? duration : (bestPlain.duration ?? duration)
                return Self.parsePlainLyrics(plain, duration: dur)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchFreeQuerySearch(query: String, expectedTitle: String, expectedArtist: String, duration: Double) async -> [LyricLine]? {
        var components = URLComponents(string: "\(baseURL)/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
            let targetTitle = expectedTitle.lowercased()
            let targetArtist = expectedArtist.lowercased()

            let scored = results.sorted { a, b in
                Self.scoreCandidate(a, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration) >
                Self.scoreCandidate(b, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration)
            }

            if let bestSynced = scored.first(where: {
                ($0.syncedLyrics ?? "").isEmpty == false &&
                Self.scoreCandidate($0, targetTitle: targetTitle, targetArtist: targetArtist, targetDuration: duration) >= 115
            }), let lrc = bestSynced.syncedLyrics {
                return Self.parseLRC(lrc, targetDuration: duration, candidateDuration: bestSynced.duration ?? 0)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchLyricsOvh(title: String, artist: String, duration: Double) async -> [LyricLine]? {
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyrics = json["lyrics"] as? String,
                  !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return Self.parsePlainLyrics(lyrics, duration: duration)
        } catch {
            return nil
        }
    }

    private static func scoreCandidate(_ candidate: LRCLibResponse, targetTitle: String, targetArtist: String, targetDuration: Double) -> Int {
        var score = 0
        if !(candidate.syncedLyrics ?? "").isEmpty {
            score += 100
        }
        let cTitle = cleanTrackTitle(candidate.trackName ?? "").lowercased()
        if cTitle == targetTitle {
            score += 45
        } else if cTitle.contains(targetTitle) || targetTitle.contains(cTitle) {
            score += 20
        } else {
            score -= 40
        }

        let cArtist = cleanArtistName(candidate.artistName ?? "").lowercased()
        if !targetArtist.isEmpty {
            if cArtist == targetArtist {
                score += 55
            } else if cArtist.contains(targetArtist) || targetArtist.contains(cArtist) {
                score += 30
            } else {
                score -= 45
            }
        }

        if targetDuration > 5, let cDur = candidate.duration, cDur > 0 {
            let diff = abs(cDur - targetDuration)
            if diff <= 1.5 {
                score += 65
            } else if diff <= 3.0 {
                score += 45
            } else if diff <= 6.0 {
                score += 20
            } else if diff <= 15.0 {
                score -= 20
            } else {
                // Strong penalty for duration mismatch > 15s (e.g., MV intro/outro vs radio edit or wrong song)
                score -= 90
            }
        }
        return score
    }

    // MARK: - Title & Artist Normalization for YouTube Music & Spotify

    public static func cleanTrackTitle(_ raw: String) -> String {
        var s = raw
        let patterns = [
            "(?i)\\s*[\\(\\[](official\\s*(music\\s*)?video|official\\s*audio|official\\s*lyric\\s*video|lyric\\s*video|lyrics|audio|mv|m/v|visualizer|hd|4k|remastered(\\s*\\d{4})?|live[^\\)\\]]*)[\\)\\]]",
            "(?i)\\s+-\\s+(remastered(\\s*\\d{4})?|single\\s*version|album\\s*version|live.*)$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func cleanArtistName(_ raw: String) -> String {
        var s = raw
        // Strip leading/trailing decorative star/heart/musical symbols (e.g. "☆Waru Leaf☆" -> "Waru Leaf")
        s = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let patterns = [
            "(?i)\\s*-\\s*topic$",
            "(?i)vevo$",
            "(?i)\\s*official$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        // If multiple artists are separated by "•", "&", or ",", take primary artist for clean lookup
        if let first = s.components(separatedBy: ",").first {
            s = first
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func cleanAlbumName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        // Ignore YouTube Music video view/like counts or year strings masquerading as album names
        let lower = s.lowercased()
        if lower.contains("views") || lower.contains("ditonton") || lower.contains("likes") || lower.contains("suka") || lower.contains("subscribers") {
            return ""
        }
        return s
    }

    // MARK: - Secondary Provider: NetEase Cloud Music Synced LRC

    private func fetchNetEaseSyncedLRC(title: String, artist: String, duration: Double) async -> [LyricLine]? {
        let query = artist.isEmpty ? title : "\(title) \(artist)"
        var searchComp = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")
        searchComp?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = searchComp?.url else { return nil }

        var req = URLRequest(url: searchURL)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = root["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]],
                  let firstSong = songs.first,
                  let songId = firstSong["id"] as? Int else {
                return nil
            }

            guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(songId)&lv=-1&kv=-1&tv=-1") else {
                return nil
            }
            var lyricReq = URLRequest(url: lyricURL)
            lyricReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

            let (lData, lResp) = try await session.data(for: lyricReq)
            guard let lHttp = lResp as? HTTPURLResponse, lHttp.statusCode == 200,
                  let lRoot = try JSONSerialization.jsonObject(with: lData) as? [String: Any],
                  let lrcObj = lRoot["lrc"] as? [String: Any],
                  let lrcText = lrcObj["lyric"] as? String,
                  !lrcText.isEmpty else {
                return nil
            }

            let parsed = Self.parseLRC(lrcText)
            return parsed.isEmpty ? nil : parsed
        } catch {
            return nil
        }
    }

    // MARK: - LRC & Plain Lyrics Parsers

    public static func parseLRC(_ lrc: String, targetDuration: Double = 0, candidateDuration: Double = 0) -> [LyricLine] {
        struct RawEntry {
            let time: Double
            let text: String
        }

        // If the playing video/track in YouTube Music is longer than the studio audio LRC by 2..20s
        // (for example due to an MV intro logo before the music starts), shift LRC timestamps forward
        // so lyrics do not appear too early!
        let introTimeOffset: Double
        if targetDuration > 15 && candidateDuration > 15 {
            let delta = targetDuration - candidateDuration
            if delta >= 2.0 && delta <= 20.0 {
                introTimeOffset = delta
            } else {
                introTimeOffset = 0
            }
        } else {
            introTimeOffset = 0
        }

        var rawEntries: [RawEntry] = []
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: nsRange) else { continue }

            guard let minRange = Range(match.range(at: 1), in: trimmed),
                  let secRange = Range(match.range(at: 2), in: trimmed),
                  let textRange = Range(match.range(at: 4), in: trimmed) else { continue }

            let minutes = Double(trimmed[minRange]) ?? 0
            let seconds = Double(trimmed[secRange]) ?? 0
            var subseconds: Double = 0
            if match.range(at: 3).location != NSNotFound,
               let subRange = Range(match.range(at: 3), in: trimmed) {
                let subStr = String(trimmed[subRange])
                let divisor = pow(10.0, Double(subStr.count))
                subseconds = (Double(subStr) ?? 0) / divisor
            }

            let time = minutes * 60.0 + seconds + subseconds + introTimeOffset
            let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
            rawEntries.append(RawEntry(time: time, text: text))
        }

        rawEntries.sort { $0.time < $1.time }
        guard !rawEntries.isEmpty else { return [] }

        var lines: [LyricLine] = []

        // 1. If the first vocal line starts after 4.0 seconds, insert an intro "♪ Music Only ♪"
        if let firstNonEmpty = rawEntries.first(where: { !isBlankOrInstrumentalMarker($0.text) }),
           firstNonEmpty.time >= 4.0 {
            lines.append(LyricLine(time: 0.0, text: LyricLine.instrumentalLabel, isInstrumental: true))
        }

        // 2. Process all timestamped entries:
        //    - Explicit empty LRC lines (`[mm:ss.xx]`) or instrumental markers (`♪`, `[Instrumental]`, etc.) become "♪ Music Only ♪"
        //    - Long gaps (>= 11s) between two vocal lines automatically get a mid-song "♪ Music Only ♪" interlude after the vocal line finishes (~5.5s)
        for i in 0..<rawEntries.count {
            let entry = rawEntries[i]
            if isBlankOrInstrumentalMarker(entry.text) {
                if lines.last?.isInstrumental != true {
                    lines.append(LyricLine(time: entry.time, text: LyricLine.instrumentalLabel, isInstrumental: true))
                }
            } else {
                lines.append(LyricLine(time: entry.time, text: entry.text, isInstrumental: false))

                if i + 1 < rawEntries.count {
                    let nextEntry = rawEntries[i + 1]
                    let gap = nextEntry.time - entry.time
                    if !isBlankOrInstrumentalMarker(nextEntry.text) && gap >= 11.0 {
                        let estimatedVocalDuration = min(6.5, max(3.8, Double(entry.text.count) * 0.11))
                        if gap - estimatedVocalDuration >= 4.0 {
                            lines.append(
                                LyricLine(
                                    time: entry.time + estimatedVocalDuration,
                                    text: LyricLine.instrumentalLabel,
                                    isInstrumental: true
                                )
                            )
                        }
                    }
                }
            }
        }

        return lines
    }

    private static func isBlankOrInstrumentalMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let lower = t.lowercased()
        let markers = [
            "♪", "♫", "♬", "🎵", "🎶",
            "instrumental", "[instrumental]", "(instrumental)",
            "music", "[music]", "(music)", "music only", "[music only]",
            "interlude", "[interlude]", "(interlude)",
            "solo", "[guitar solo]", "(guitar solo)"
        ]
        if markers.contains(lower) { return true }
        // Also match lines composed solely of music note symbols or dots
        let stripped = t.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
            $0 != "♪" && $0 != "♫" && $0 != "♬" && $0 != "." && $0 != "-" && $0 != "~"
        }
        return stripped.isEmpty
    }

    public static func parsePlainLyrics(_ plain: String, duration: Double) -> [LyricLine] {
        let nonEmpty = plain
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return [] }

        let effectiveDuration = duration > 15 ? duration * 0.92 : Double(nonEmpty.count) * 3.5
        let step = max(1.8, effectiveDuration / Double(nonEmpty.count))

        return nonEmpty.enumerated().map { idx, lineText in
            LyricLine(time: Double(idx) * step, text: lineText)
        }
    }
}
