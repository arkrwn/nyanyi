import Foundation

public struct LyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let time: Double
    public let text: String
    public let annotations: [AnnotatedChar]
    public let hasPhonetics: Bool

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
        let chars = PhoneticConverter.annotate(text)
        self.annotations = chars
        self.hasPhonetics = chars.contains { !$0.phonetic.isEmpty }
    }

    public static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time == rhs.time && lhs.text == rhs.text && lhs.hasPhonetics == rhs.hasPhonetics
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
        let cacheKey = "\(cleanedArtist)|\(cleanedTitle)"

        if let cached = cache[cacheKey] {
            return cached
        }

        if let lines = await fetchExact(track: track), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        if cleanedTitle != track.title || cleanedArtist != track.artist {
            let cleanedTrack = TrackInfo(
                title: cleanedTitle,
                artist: cleanedArtist,
                album: track.album,
                duration: track.duration,
                sourceName: track.sourceName
            )
            if let lines = await fetchExact(track: cleanedTrack), !lines.isEmpty {
                cache[cacheKey] = lines
                return lines
            }
        }

        if let lines = await fetchSearch(title: cleanedTitle, artist: cleanedArtist, duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        if let lines = await fetchSearch(title: cleanedTitle, artist: "", duration: track.duration), !lines.isEmpty {
            cache[cacheKey] = lines
            return lines
        }

        return []
    }

    private func fetchExact(track: TrackInfo) async -> [LyricLine]? {
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
                return Self.parseLRC(lrc)
            }
            if let plain = result.plainLyrics, !plain.isEmpty {
                let dur = result.duration ?? track.duration
                return Self.parsePlainLyrics(plain, duration: dur)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchSearch(title: String, artist: String, duration: Double) async -> [LyricLine]? {
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
            if let syncedMatch = results.first(where: { ($0.syncedLyrics ?? "").isEmpty == false }),
               let lrc = syncedMatch.syncedLyrics {
                return Self.parseLRC(lrc)
            }
            if let plainMatch = results.first(where: { ($0.plainLyrics ?? "").isEmpty == false }),
               let plain = plainMatch.plainLyrics {
                let dur = plainMatch.duration ?? duration
                return Self.parsePlainLyrics(plain, duration: dur)
            }
            return nil
        } catch {
            return nil
        }
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
        let patterns = [
            "(?i)\\s*-\\s*topic$",
            "(?i)vevo$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        if let first = s.components(separatedBy: ",").first {
            s = first
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - LRC & Plain Lyrics Parsers

    public static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
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

            let time = minutes * 60.0 + seconds + subseconds
            let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)

            if !text.isEmpty {
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
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
