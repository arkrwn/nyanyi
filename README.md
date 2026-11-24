# Nyanyi

Lightweight native macOS menu bar application that displays real-time synchronized lyrics for **Spotify** and **YouTube Music**, supporting **all languages** with automatic phonetic romanization for non-Latin scripts.

Released under the [MIT License](LICENSE). Recreated and expanded from [lyricue](https://github.com/feryadialoi/lyricue).

---

## Features

- **Spotify + YouTube Music on macOS**
  - **Spotify**: Native macOS `Spotify.app` integration via AppleScript (`tell application "Spotify"`).
  - **YouTube Music (Web Browsers)**: Automatic tab detection for `music.youtube.com` across **Google Chrome**, **Arc**, **Brave Browser**, **Microsoft Edge**, **Safari**, **Chromium**, and **Vivaldi** (reads track title, artist, album, and `<video>` playback position, with automatic tab-title fallback).
  - **YouTube Music Desktop App**: Supports `th-ch/youtube-music` / `ytmdesktop` local companion API (`http://127.0.0.1:26538/api/v1/song-info`).
  - **Source Selector**: Switch between `Auto (Spotify + YouTube Music)`, `Spotify Only`, or `YouTube Music Only` from the menu bar.
- **All-Language Lyrics & Universal Phonetics**
  - **Latin-Script Languages** (Indonesian, English, Spanish, French, German, Malay, Tagalog, Portuguese, Italian, Turkish, Vietnamese, etc.) render cleanly without redundant phonetic clutter.
  - **Non-Latin Scripts** automatically show word- or character-level romanization above the lyrics using macOS native ICU `CFStringTransform` and `CFStringTokenizer`:
    - **Chinese (Hanzi)** -> Pinyin with tone marks (`kCFStringTransformMandarinLatin`)
    - **Japanese (Kanji / Hiragana / Katakana)** -> Word-level Romaji (`CFStringTokenizer` `ja` + `kCFStringTransformLatinHiragana`)
    - **Korean (Hangul)** -> Revised Romanization (`kCFStringTransformLatinHangul`)
    - **Arabic / Persian / Urdu** -> Latin transliteration (`kCFStringTransformLatinArabic`)
    - **Cyrillic (Russian, Ukrainian, etc.)** -> Latin transliteration (`kCFStringTransformLatinCyrillic`)
    - **Thai** -> Word-segmented Latin romanization (`CFStringTokenizer` `th` + `kCFStringTransformLatinThai`)
    - **Greek & Hebrew** -> Latin transliteration (`kCFStringTransformLatinGreek`, `kCFStringTransformLatinHebrew`)
    - **Indic & All Other Scripts** (Devanagari/Hindi, Bengali, Tamil, Telugu, Georgian, Armenian, Khmer, etc.) -> Universal ICU `Any-Latin; Latin-ASCII` transliteration
  - **Phonetic Modes**: Choose `Auto (Non-Latin -> Latin)`, `All Scripts`, or `Off` from the menu bar.
- **Three Display Modes**
  - **Floating**: Translucent frosted-glass HUD overlay (`NSVisualEffectView`), draggable and resizable anywhere on screen.
  - **Corner**: Compact PiP-style overlay that snaps to the nearest screen corner on drag release.
  - **Menu Bar**: Live scrolling lyric ticker directly inside the macOS status bar (`CATextLayer`).
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

## YouTube Music Browser Setup (Optional for Exact Sub-Second Sync)

Nyanyi detects `music.youtube.com` tabs in Chrome, Arc, Brave, Edge, and Safari out of the box:

- **Default (Zero Setup)**: Reads the song title and artist from the browser tab title and advances lyrics smoothly.
- **Exact Sub-Second `<video>` Timestamp Sync**:
  - **Chrome / Brave / Arc / Edge**: In the browser menu bar, enable **View -> Developer -> Allow JavaScript from Apple Events**.
  - **Safari**: Enable **Develop -> Allow JavaScript from Apple Events**.
  - **YouTube Music Desktop App (`th-ch/youtube-music`)**: Enable the **API Server** plugin on default port `26538` (no authentication required for read-only `/api/v1/song-info`).

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

## License

[MIT License](LICENSE)
