# Nyanyi

## Tujuan

Recreate aplikasi macOS live lyrics overlay dari `feryadialoi/lyricue` dengan lisensi **MIT**, dukungan **semua bahasa** (Latin maupun non-Latin dengan transliterasi otomatis), serta dukungan player **Spotify** dan **YouTube Music** di macOS.

## Scope

- Platform saat ini: **macOS 13+** (Swift 5.9, SwiftUI + AppKit, zero external dependencies).
- Lisensi: **MIT License**.
- Sumber player:
  - **Spotify** (`Spotify.app` lewat AppleScript).
  - **YouTube Music Web** (`music.youtube.com` di Google Chrome, Arc, Brave Browser, Microsoft Edge, Safari, Chromium, Vivaldi lewat AppleScript DOM `<video>` + fallback tab title).
  - **YouTube Music Desktop App** (`th-ch/youtube-music` companion API di `127.0.0.1:26538/api/v1/song-info`).
- Bahasa dan fonetik:
  - Semua bahasa berskrip Latin (Indonesia, Inggris, Spanyol, Prancis, Jerman, Melayu, Tagalog, Turki, Vietnam, dll.) ditampilkan bersih tanpa duplikasi anotasi, atau normalisasi diakritik pada mode `All Scripts`.
  - Semua skrip non-Latin (Hanzi Mandarin -> Pinyin, Jepang Kanji/Kana -> Romaji per kata, Korea Hangul -> Revised Romanization, Arab, Sirilik, Thailand per kata, Yunani, Ibrani, Devanagari/Hindi, serta skrip non-Latin lain lewat ICU `Any-Latin`) otomatis menampilkan panduan baca di atas kata/karakter.
- Sumber lirik: **LRCLIB** (`https://lrclib.net/api`) dengan pembersih suffix YouTube Music / Spotify (`- Topic`, `(Official Video)`, `(Official Audio)`, `[MV]`, dll.) serta fallback `plainLyrics`.

## Repository

- GitHub: `https://github.com/arkrwn/nyanyi`
- Lokasi di arkspace: `projects/nyanyi/`
- Owner: `arkrwn`
