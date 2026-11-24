# Changelog

All notable changes to **Nyanyi** are documented in this file.

## [0.0.14] - 2026-11-24

### Added
- **Bottom Navbar (Apple Bar)** display mode: full-width bar docked at the bottom edge of the screen with Apple Menu Bar height, adaptive material, playback controls, live lyrics, and `mm:ss / mm:ss` time display.
- **Bottom Navbar: Auto-Hide on Pause** toggle in the `Display` menu (default `Off` so controls remain accessible while paused).
- **Playback Controls & Time Display** (`Previous`, `Play / Pause`, `Next`, and `mm:ss / mm:ss` progress bar) across all overlay modes and the Menu Bar menu.
- **Native macOS Hardware Media Keys (`IOHIDPostEvent`)** for instant (~0ms) `Previous`, `Play / Pause`, and `Next` control, with automatic **Accessibility** permission prompt (`AXIsProcessTrustedWithOptions`).
- **Compact Overlay Sizes** re-calibrated (`Small` `0.65x`, `Medium` `0.82x`, `Large` `1.0x`).

### Changed
- Replaced interactive/scroll seek controls with a clean read-only `TrackProgressBar` and simplified overlay controls to **Previous / Play-Pause / Next**.
- Updated `README.md` with Accessibility permission instructions and Bottom Navbar documentation.

### Removed
- Removed `[Experimental] Scroll to Seek` and interactive fast-forward/backward scrubbing across all modes.

## [0.0.13] - 2026-11-24

### Added
- Initial public release (`Nyanyi.dmg` and `Nyanyi-macOS.zip`) with Apple Liquid Glass UI, automatic Google Chrome (`music.youtube.com` / `open.spotify.com`) and `Spotify.app` detection, universal ICU `CFStringTransform` transliteration, draggable `Subtitle (Movie Style)` mode, `Music Only` indicator, auto-minimize on pause, and multi-source lyrics lookup.
