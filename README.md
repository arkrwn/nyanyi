# Nyanyi

Lightweight native macOS menu bar application that displays real-time synchronized lyrics for **Spotify** and **YouTube Music**, supporting **all languages** with automatic phonetic romanization for non-Latin scripts.

> **Acknowledgements & Inspiration**
> Inspired by [lyricue](https://github.com/feryadialoi/lyricue) created by [@feryadialoi](https://github.com/feryadialoi). Huge appreciation to Feryadi Aloi for the original macOS overlay concept and design foundation.

Released under the [MIT License](LICENSE).

---

## Features

- **100% Automatic Player Detection (Google Chrome + Spotify on macOS)**
  - Zero manual player selection needed: Nyanyi automatically detects whichever player is actively playing.
  - **Google Chrome (Tested & Recommended)**: Automatic tab detection for **YouTube Music** (`music.youtube.com`) and **Spotify Web Player** (`open.spotify.com`) inside Google Chrome.
  - **Spotify Desktop App**: Native macOS `Spotify.app` integration via AppleScript (`tell application "Spotify"`).
  - *Note: Currently only **Google Chrome** has been tested and verified for browser playback (`music.youtube.com` & `open.spotify.com`). Other browsers (Safari, Arc, Brave, Edge) are not tested yet.*
- **100% Automatic All-Language Lyrics & Universal Phonetics**
  - Zero language configuration: script detection runs automatically per lyric line.
  - **Latin-Script Languages** (Indonesian, English, Spanish, French, German, Malay, Tagalog, Portuguese, Italian, Turkish, Vietnamese, etc.) render cleanly without redundant phonetic clutter.
  - **Non-Latin Scripts** automatically show word- or character-level romanization above the lyrics using macOS native ICU `CFStringTransform` and `CFStringTokenizer`:
    - **Chinese (Hanzi)** -> Pinyin with tone marks (`kCFStringTransformMandarinLatin`)
    - **Japanese (Kanji / Hiragana / Katakana)** -> Word-level Romaji (`CFStringTokenizer` `ja` + `kCFStringTransformLatinHiragana`)
    - **Korean (Hangul)** -> Revised Romanization (`kCFStringTransformLatinHangul`)
    - **Arabic / Persian / Urdu** -> Latin transliteration
    - **Cyrillic (Russian, Ukrainian, etc.)** -> Latin transliteration
    - **Thai** -> Word-segmented Latin romanization (`CFStringTokenizer` `th`)
    - **Greek, Hebrew, Devanagari/Hindi & All Other Non-Latin Scripts** -> Universal ICU `Any-Latin` transliteration
- **Four Display Modes (Visible Even Over Full-Screen Apps)**
  - **Floating Card**: Translucent Apple Liquid Glass HUD overlay (`NSVisualEffectView`), draggable and resizable anywhere on screen.
  - **Corner Card**: Compact PiP-style overlay that snaps to the nearest screen corner on drag release.
  - **Subtitle (Movie Style)**: Dynamic 2-line Apple Glass cinema subtitle pill that tightly wraps its text and can be dragged freely anywhere on screen (top, center, bottom). Every pixel outside the subtitle pill itself passes clicks directly to the apps behind it.
  - **Menu Bar Ticker**: Live scrolling lyric ticker directly inside the macOS status bar.
  - **Full-Screen Support**: Uses `NSPanel` with `.screenSaver` window level, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `hidesOnDeactivate = false` so lyrics stay visible even while games, browsers, or video players are in macOS full-screen mode.
- **Smart Lyrics Lookup ([LRCLIB](https://lrclib.net))**
  - Automatically strips YouTube Music and Spotify suffixes (`- Topic`, `(Official Music Video)`, `(Official Audio)`, `(Lyric Video)`, `[MV]`, `Remastered`, etc.) for high match rates.
  - Supports both time-synced LRC (`syncedLyrics`) and auto-paced `plainLyrics` fallback.
- **Zero External Dependencies**
  - Pure Swift + SwiftUI + AppKit (`macOS 13+`).

---

## Install on macOS

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/arkrwn/nyanyi/main/install.sh | bash
```

Requires Xcode Command Line Tools (`xcode-select --install`).

### Build from source

```bash
git clone https://github.com/arkrwn/nyanyi.git
cd nyanyi

# Create Nyanyi.app bundle
chmod +x package.sh
./package.sh

# Run directly or copy to /Applications
open Nyanyi.app
cp -R Nyanyi.app /Applications/

# Optional: build a distributable DMG
./package.sh --dmg
```

---

## Required Google Chrome Setup (YouTube Music & Spotify Web)

> **Important**: Currently, browser playback is **only tested and supported on Google Chrome** (`music.youtube.com` and `open.spotify.com`). Other browsers have not been tested yet.

For **Nyanyi** to read the active song metadata (`navigator.mediaSession.metadata`), detect track changes automatically, and sync exact sub-second playback timestamps from **Google Chrome**:

1. Open **Google Chrome** on your Mac.
2. In the macOS top menu bar, click **View -> Developer -> Allow JavaScript from Apple Events** (make sure it has a checkmark ✓).
3. Play any song on [YouTube Music](https://music.youtube.com) or [Spotify Web Player](https://open.spotify.com) in Google Chrome.

---

## Project Structure

```
nyanyi/
├── .github/workflows/ci.yml             # GitHub Actions macOS CI (swift test + package.sh --dmg)
├── LICENSE                              # MIT License
├── Package.swift                        # Swift Package Manager manifest (macOS 13+)
├── Info.plist                           # App bundle metadata (LSUIElement + AppleEvents usage)
├── AppIcon.icns                         # macOS application icon
├── package.sh                           # Builds Nyanyi.app and optional Nyanyi.dmg (macOS)
├── install.sh                           # One-line curl installer to /Applications
├── Sources/
│   ├── NyanyiCore/                      # Core lyrics, phonetics, and player monitor module
│   │   ├── DisplaySettings.swift        # Persisted display mode, corner position, source, phonetic mode
│   │   ├── LyricsService.swift          # LRCLIB client, YouTube/Spotify title cleaner, LRC + plainLyrics parser
│   │   ├── LyricsViewModel.swift        # Combine coordinator bridging PlayerMonitor, LyricsService, and UI
│   │   ├── PhoneticConverter.swift      # Universal script detector & ICU CFStringTransform romanizer
│   │   └── PlayerMonitor.swift          # Spotify AppleScript + YouTube Music Browser/Desktop polling + 4Hz interpolation
│   └── Nyanyi/                          # AppKit + SwiftUI executable target
│       ├── NyanyiApp.swift              # @main entry point (.accessory activation policy)
│       ├── AppDelegate.swift            # Menu bar item, Display / Player Source / Phonetics menus
│       ├── OverlayWindowController.swift# Always-on-top NSPanel with corner magnetic snap
│       ├── ContentView.swift            # SwiftUI HUD card with source badge & ruby phonetic annotations
│       └── MenuBarTicker.swift          # Core Animation marquee ticker in NSStatusBarButton
└── Tests/NyanyiTests/
    └── NyanyiTests.swift                # Unit tests for multi-language phonetics, LRC parsing, & player parsers
```

---

## Credits & Appreciation

This project is inspired by [**feryadialoi/lyricue**](https://github.com/feryadialoi/lyricue) by [**@feryadialoi**](https://github.com/feryadialoi). Special thanks and appreciation for building the original macOS live lyrics overlay that sparked **Nyanyi**.

---

## License

[MIT License](LICENSE)
