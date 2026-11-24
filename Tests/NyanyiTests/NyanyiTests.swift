import XCTest
@testable import NyanyiCore

final class NyanyiTests: XCTestCase {

    // MARK: - Script Detection Across Languages

    func testDetectScriptAllLanguages() {
        XCTAssertEqual(PhoneticConverter.detectScript("Menghitung hari detik demi detik"), .latin)
        XCTAssertEqual(PhoneticConverter.detectScript("Bohemian Rhapsody"), .latin)
        XCTAssertEqual(PhoneticConverter.detectScript("你问我爱你有多深"), .chinese)
        XCTAssertEqual(PhoneticConverter.detectScript("夜に駆ける"), .japanese)
        XCTAssertEqual(PhoneticConverter.detectScript("사랑을 했다 우리가 만나"), .korean)
        XCTAssertEqual(PhoneticConverter.detectScript("يا حبيبي تعال"), .arabic)
        XCTAssertEqual(PhoneticConverter.detectScript("Группа крови на рукаве"), .cyrillic)
        XCTAssertEqual(PhoneticConverter.detectScript("รักเธอเสมอ"), .thai)
        XCTAssertEqual(PhoneticConverter.detectScript("नमस्ते दुनिया"), .devanagari)
        XCTAssertEqual(PhoneticConverter.detectScript("Καλημέρα"), .greek)
        XCTAssertEqual(PhoneticConverter.detectScript("שלום עולם"), .hebrew)
    }

    // MARK: - Automatic Phonetic Romanization

    func testLatinScriptHasNoRedundantPhonetics() {
        let tokens = PhoneticConverter.annotate("Jangan pernah menyerah")
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertTrue(tokens.allSatisfy { $0.phonetic.isEmpty })
    }

    func testChinesePinyinAnnotation() {
        let tokens = PhoneticConverter.annotate("你好")
        XCTAssertEqual(tokens.count, 2)
        XCTAssertFalse(tokens[0].phonetic.isEmpty)
        XCTAssertFalse(tokens[1].phonetic.isEmpty)
    }

    func testJapaneseRomajiAnnotation() {
        let tokens = PhoneticConverter.annotate("さくら")
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertTrue(tokens.contains { !$0.phonetic.isEmpty })
    }

    func testKoreanHangulAnnotation() {
        let tokens = PhoneticConverter.annotate("사랑")
        XCTAssertEqual(tokens.count, 2)
        XCTAssertFalse(tokens[0].phonetic.isEmpty)
        XCTAssertFalse(tokens[1].phonetic.isEmpty)
    }

    func testNonLatinWordLevelAnnotations() {
        let cyrillic = PhoneticConverter.annotate("Привет мир")
        XCTAssertTrue(cyrillic.contains { !$0.phonetic.isEmpty })

        let arabic = PhoneticConverter.annotate("مرحبا")
        XCTAssertTrue(arabic.contains { !$0.phonetic.isEmpty })

        let thai = PhoneticConverter.annotate("สวัสดี")
        XCTAssertTrue(thai.contains { !$0.phonetic.isEmpty })
    }

    // MARK: - Display Modes (Including Movie Subtitle Top & Bottom)

    func testDisplayModesIncludeMovieSubtitles() {
        XCTAssertTrue(DisplayMode.subtitleBottom.isSubtitleStyle)
        XCTAssertTrue(DisplayMode.subtitleTop.isSubtitleStyle)
        XCTAssertFalse(DisplayMode.floating.isSubtitleStyle)
        XCTAssertFalse(DisplayMode.corner.isSubtitleStyle)
        XCTAssertFalse(DisplayMode.menuBar.isSubtitleStyle)
        XCTAssertEqual(DisplayMode.allCases.count, 5)
    }

    // MARK: - LRC & Plain Lyrics Parsing

    func testParseSyncedLRC() {
        let sampleLRC = """
        [00:12.50] Baris pertama lagu
        [00:18.25] 你好世界
        [01:02.100] Baris ketiga
        """
        let lines = LyricsService.parseLRC(sampleLRC)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 12.50, accuracy: 0.01)
        XCTAssertEqual(lines[0].text, "Baris pertama lagu")
        XCTAssertFalse(lines[0].hasPhonetics)

        XCTAssertEqual(lines[1].time, 18.25, accuracy: 0.01)
        XCTAssertEqual(lines[1].text, "你好世界")
        XCTAssertTrue(lines[1].hasPhonetics)

        XCTAssertEqual(lines[2].time, 62.10, accuracy: 0.01)
    }

    func testParsePlainLyricsAutoPacing() {
        let plain = """
        First line
        Second line
        Third line
        """
        let lines = LyricsService.parsePlainLyrics(plain, duration: 90)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 0.0, accuracy: 0.01)
        XCTAssertGreaterThan(lines[1].time, lines[0].time)
        XCTAssertGreaterThan(lines[2].time, lines[1].time)
    }

    // MARK: - YouTube Music & Spotify Title/Artist Normalization

    func testCleanTrackTitleAndArtistName() {
        XCTAssertEqual(
            LyricsService.cleanTrackTitle("Hati-Hati di Jalan (Official Music Video)"),
            "Hati-Hati di Jalan"
        )
        XCTAssertEqual(
            LyricsService.cleanTrackTitle("アイドル [Official Video]"),
            "アイドル"
        )
        XCTAssertEqual(
            LyricsService.cleanTrackTitle("Numb (Official Lyric Video)"),
            "Numb"
        )
        XCTAssertEqual(
            LyricsService.cleanArtistName("Tulus - Topic"),
            "Tulus"
        )
        XCTAssertEqual(
            LyricsService.cleanArtistName("YOASOBI - Topic"),
            "YOASOBI"
        )
    }

    // MARK: - Spotify & YouTube Music Player Snapshot Parsing

    func testParseSpotifyAppleScriptOutput() {
        let raw = "playing|||Hati-Hati di Jalan|||Tulus|||Manusia|||242000|||45.5"
        let snap = PlayerMonitor.parseSpotifyAppleScriptResult(raw)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.track.title, "Hati-Hati di Jalan")
        XCTAssertEqual(snap?.track.artist, "Tulus")
        XCTAssertEqual(snap?.track.album, "Manusia")
        XCTAssertEqual(snap?.track.duration ?? 0, 242.0, accuracy: 0.01)
        XCTAssertEqual(snap?.position ?? 0, 45.5, accuracy: 0.01)
        XCTAssertEqual(snap?.isPlaying, true)
        XCTAssertEqual(snap?.track.sourceName, "Spotify")
    }

    func testParseYouTubeMusicBrowserJSOutput() {
        let monitor = PlayerMonitor(autoStart: false)
        let raw = "JS|||playing|||夜に駆ける|||YOASOBI|||THE BOOK|||261.0|||88.25|||夜に駆ける - YOASOBI - YouTube Music"
        let snap = monitor.parseYouTubeMusicAppleScriptResult(raw, sourceLabel: "YouTube Music (Google Chrome)")
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.track.title, "夜に駆ける")
        XCTAssertEqual(snap?.track.artist, "YOASOBI")
        XCTAssertEqual(snap?.track.album, "THE BOOK")
        XCTAssertEqual(snap?.track.duration ?? 0, 261.0, accuracy: 0.01)
        XCTAssertEqual(snap?.position ?? 0, 88.25, accuracy: 0.01)
        XCTAssertEqual(snap?.isPlaying, true)
        XCTAssertEqual(snap?.track.sourceName, "YouTube Music (Google Chrome)")
    }

    func testParseYouTubeMusicTabTitleFallback() {
        let parsed = PlayerMonitor.parseTabTitle("▶ Sial - Mahalini - YouTube Music")
        XCTAssertEqual(parsed.title, "Sial")
        XCTAssertEqual(parsed.artist, "Mahalini")
    }

    func testParseYouTubeMusicDesktopCompanionJSON() {
        let jsonString = """
        {
            "title": "Evaluasi",
            "artist": "Hindia",
            "album": "Menari Dengan Bayangan",
            "isPaused": false,
            "elapsedSeconds": 32.4,
            "songDuration": 195.0
        }
        """
        let snap = PlayerMonitor.parseYouTubeMusicDesktopJSON(Data(jsonString.utf8))
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.track.title, "Evaluasi")
        XCTAssertEqual(snap?.track.artist, "Hindia")
        XCTAssertEqual(snap?.track.sourceName, "YouTube Music (App)")
        XCTAssertEqual(snap?.isPlaying, true)
        XCTAssertEqual(snap?.position ?? 0, 32.4, accuracy: 0.01)
    }
}
