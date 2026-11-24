import SwiftUI
import AppKit
import NyanyiCore

// MARK: - Native Apple Liquid Frosted Glass Material (NSVisualEffectView)

struct AppleGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 20

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.layer?.cornerRadius = cornerRadius
        nsView.appearance = NSAppearance(named: .aqua)
    }
}

// MARK: - Main Overlay Content View

struct ContentView: View {
    @ObservedObject var viewModel: LyricsViewModel
    @ObservedObject var displaySettings: DisplaySettings

    private var isCompact: Bool { displaySettings.mode == .corner }
    private var sizeScale: CGFloat { CGFloat(displaySettings.size.scaleFactor) }

    var body: some View {
        if displaySettings.mode.isSubtitleStyle {
            movieSubtitleGlassView
        } else {
            appleGlassCardView
        }
    }

    // MARK: - 1. Apple Glass Movie-Style Two-Line Subtitle Mode (Static Size per Small/Medium/Large)

    private var movieSubtitleGlassView: some View {
        let pair = activeAndNextSubtitleLines
        let activeFontSize: CGFloat = round(20 * sizeScale)
        let nextFontSize: CGFloat = round(13.5 * sizeScale)
        let radius: CGFloat = round(20 * sizeScale)

        return ZStack {
            if let currentLine = pair.current {
                ZStack {
                    AppleGlassBackground(material: .popover, cornerRadius: radius)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: round(4 * sizeScale)) {
                        // Line 1: Active lyric line (calm, steady, no jumping)
                        Group {
                            if currentLine.isInstrumental {
                                HStack(spacing: 7) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: round(16 * sizeScale), weight: .bold))
                                        .foregroundColor(Color(red: 0.05, green: 0.38, blue: 0.85))
                                    Text("Music Only")
                                        .font(.system(size: activeFontSize, weight: .bold, design: .rounded))
                                        .italic()
                                        .foregroundColor(Color(red: 0.05, green: 0.36, blue: 0.80))
                                    Image(systemName: "guitars.fill")
                                        .font(.system(size: round(14 * sizeScale), weight: .semibold))
                                        .foregroundColor(Color(red: 0.05, green: 0.38, blue: 0.85).opacity(0.85))
                                }
                            } else if currentLine.hasPhonetics {
                                movieSubtitleAnnotatedLine(currentLine, isPrimary: true)
                            } else {
                                Text(currentLine.text)
                                    .font(.system(size: activeFontSize, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.black.opacity(0.95))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.50)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Subtle liquid glass progress indicator bar for current line
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.08))
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.05, green: 0.38, blue: 0.85).opacity(0.85),
                                                Color(red: 0.12, green: 0.58, blue: 0.96).opacity(0.95)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(6, geo.size.width * CGFloat(viewModel.lineProgress)))
                            }
                        }
                        .frame(width: round(140 * sizeScale), height: 2.5)

                        // Line 2: Upcoming next lyric line preview (always keeps steady 2-line height)
                        Text(pair.next?.text ?? " ")
                            .font(.system(size: nextFontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.56))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, round(18 * sizeScale))
                    .padding(.vertical, round(8 * sizeScale))
                    .animation(.easeOut(duration: 0.12), value: currentLine.id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.90),
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
            } else if !viewModel.trackTitle.isEmpty {
                ZStack {
                    AppleGlassBackground(material: .popover, cornerRadius: radius)
                    Color.white.opacity(0.62)

                    HStack(spacing: 9) {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                                .colorScheme(.light)
                        } else {
                            GlowingStatusDot(isPlaying: viewModel.isPlaying)
                        }
                        Text("\(viewModel.trackTitle)\(viewModel.artist.isEmpty ? "" : " - \(viewModel.artist)")")
                            .font(.system(size: round(15 * sizeScale), weight: .bold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.88))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.88), Color.black.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeAndNextSubtitleLines: (current: LyricLine?, next: LyricLine?) {
        guard !viewModel.lines.isEmpty else { return (nil, nil) }
        if let idx = viewModel.currentLineIndex, idx >= 0, idx < viewModel.lines.count {
            let current = viewModel.lines[idx]
            let next = (idx + 1 < viewModel.lines.count) ? viewModel.lines[idx + 1] : nil
            return (current, next)
        }
        let first = viewModel.lines[0]
        let second = (viewModel.lines.count > 1) ? viewModel.lines[1] : nil
        return (first, second)
    }

    private func movieSubtitleAnnotatedLine(_ line: LyricLine, isPrimary: Bool) -> some View {
        let phoneticSize: CGFloat = round((isPrimary ? 11 : 9) * sizeScale)
        let charSize: CGFloat = round((isPrimary ? 20 : 14) * sizeScale)

        return HStack(spacing: 4) {
            ForEach(Array(line.annotations.enumerated()), id: \.offset) { _, item in
                if item.character == " " {
                    Spacer().frame(width: 6)
                } else {
                    VStack(spacing: 0) {
                        Text(item.phonetic)
                            .font(.system(size: phoneticSize, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.04, green: 0.34, blue: 0.78))
                            .lineLimit(1)
                            .fixedSize()

                        Text(item.character)
                            .font(.system(size: charSize, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.94))
                            .shadow(color: Color.white.opacity(0.6), radius: 1, x: 0, y: 0.5)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - 2. Apple Glass Multi-Line Card Overlay Mode (Floating / Corner)

    private var appleGlassCardView: some View {
        ZStack {
            // Layer 1: Native macOS behind-window frosted blur
            AppleGlassBackground(material: .popover, cornerRadius: 20)

            // Layer 2: Apple Liquid Glass specular gradient sheen for high contrast with black lyrics
            LinearGradient(
                colors: [
                    Color.white.opacity(0.64),
                    Color.white.opacity(0.42),
                    Color.white.opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                headerBar
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.03),
                                Color.black.opacity(0.12),
                                Color.black.opacity(0.03)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                if viewModel.lines.isEmpty {
                    emptyStateView
                } else {
                    lyricsScrollView
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(viewModel.isHovering ? 0.95 : 0.80),
                            Color.black.opacity(viewModel.isHovering ? 0.22 : 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.isHovering = hovering
            }
        }
    }

    // MARK: - Track Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            GlowingStatusDot(isPlaying: viewModel.isPlaying)

            if !viewModel.trackTitle.isEmpty {
                Text(viewModel.trackTitle)
                    .font(.system(size: round((isCompact ? 11 : 12.5) * sizeScale), weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.92))
                    .lineLimit(1)

                if !viewModel.artist.isEmpty {
                    Text("• \(viewModel.artist)")
                        .font(.system(size: round((isCompact ? 10 : 11.5) * sizeScale), weight: .semibold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.62))
                        .lineLimit(1)
                }
            } else {
                Text("Nyanyi")
                    .font(.system(size: round(12.5 * sizeScale), weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.75))
            }

            Spacer()

            if !viewModel.activeSourceName.isEmpty {
                Text(shortSourceBadge(viewModel.activeSourceName))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.80))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8)
                    )
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.top, isCompact ? 9 : 12)
        .padding(.bottom, isCompact ? 7 : 9)
    }

    private func shortSourceBadge(_ sourceName: String) -> String {
        if sourceName.hasPrefix("YouTube Music") {
            return "YT Music"
        }
        return sourceName
    }

    // MARK: - Scrollable Synced Lyrics (Apple Music Lyrics Style)

    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: round((isCompact ? 7 : 11) * sizeScale)) {
                    Spacer().frame(height: isCompact ? 18 : 40)

                    ForEach(Array(viewModel.lines.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(
                            line: line,
                            isCurrent: index == viewModel.currentLineIndex,
                            isPast: isPastLine(index),
                            distance: lineDistance(index),
                            lineProgress: index == viewModel.currentLineIndex ? viewModel.lineProgress : 0,
                            isCompact: isCompact,
                            sizeScale: sizeScale
                        )
                        .id(index)
                    }

                    Spacer().frame(height: isCompact ? 40 : 85)
                }
                .padding(.horizontal, isCompact ? 12 : 16)
            }
            .onChange(of: viewModel.currentLineIndex) { newIndex in
                guard let idx = newIndex else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty / Loading State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.85)
                    .colorScheme(.light)
                Text("Searching synced lyrics...")
                    .font(.system(size: round(13 * sizeScale), weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.72))
            } else if viewModel.trackTitle.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: round(28 * sizeScale), weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.50))
                Text("Play a song on YouTube Music or Spotify in Chrome")
                    .font(.system(size: round(13 * sizeScale), weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: round(24 * sizeScale), weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.50))
                Text("No lyrics found for \(viewModel.trackTitle)")
                    .font(.system(size: round(13 * sizeScale), weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func isPastLine(_ index: Int) -> Bool {
        guard let current = viewModel.currentLineIndex else { return false }
        return index < current
    }

    private func lineDistance(_ index: Int) -> Int {
        guard let current = viewModel.currentLineIndex else { return 99 }
        return abs(index - current)
    }
}

// MARK: - Glowing Live Status Dot

struct GlowingStatusDot: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            if isPlaying {
                Circle()
                    .fill(Color(red: 0.08, green: 0.72, blue: 0.28).opacity(0.32))
                    .frame(width: 13, height: 13)
            }
            Circle()
                .fill(isPlaying ? Color(red: 0.06, green: 0.68, blue: 0.24) : Color.black.opacity(0.32))
                .frame(width: 7.5, height: 7.5)
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
    }
}

// MARK: - Single Lyric Line View (Apple Music Glass Highlight + Depth Motion)

struct LyricLineView: View {
    let line: LyricLine
    let isCurrent: Bool
    let isPast: Bool
    let distance: Int
    var lineProgress: Double = 0
    var isCompact: Bool = false
    var sizeScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: isCurrent ? 4 : 0) {
            Group {
                if line.isInstrumental {
                    instrumentalView
                } else if line.hasPhonetics {
                    annotatedView
                } else {
                    plainView
                }
            }

            if isCurrent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.05, green: 0.38, blue: 0.85).opacity(0.80),
                                        Color(red: 0.12, green: 0.58, blue: 0.96).opacity(0.95)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * CGFloat(lineProgress)))
                            .animation(.linear(duration: 0.12), value: lineProgress)
                    }
                }
                .frame(width: round(96 * sizeScale), height: 2.5)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, isCurrent ? 12 : 6)
        .padding(.vertical, isCurrent ? (isCompact ? 6 : 8) : 2)
        .background(
            Group {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.75),
                                    Color.white.opacity(0.48)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.90), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
                }
            }
        )
        .scaleEffect(isCurrent ? 1.02 : 0.98)
        .opacity(lineOpacity)
        .animation(.easeOut(duration: 0.16), value: isCurrent)
        .animation(.easeOut(duration: 0.16), value: distance)
    }

    private var plainView: some View {
        let activeSize: CGFloat = round((isCompact ? 15.5 : 18.5) * sizeScale)
        let inactiveSize: CGFloat = round((isCompact ? 12.5 : 15) * sizeScale)
        return Text(line.text)
            .font(.system(
                size: isCurrent ? activeSize : inactiveSize,
                weight: isCurrent ? .bold : .semibold,
                design: .rounded
            ))
            .foregroundColor(textColor)
            .shadow(color: isCurrent ? Color.white.opacity(0.65) : .clear, radius: 1, x: 0, y: 0.5)
            .multilineTextAlignment(.center)
    }

    private var instrumentalView: some View {
        let activeSize: CGFloat = round((isCompact ? 15 : 17.5) * sizeScale)
        let inactiveSize: CGFloat = round((isCompact ? 12 : 14) * sizeScale)
        let accentColor = isCurrent
            ? Color(red: 0.05, green: 0.36, blue: 0.80)
            : Color.black.opacity(isPast ? 0.42 : 0.58)

        return HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: isCurrent ? activeSize - 2 : inactiveSize - 2, weight: .bold))
                .foregroundColor(accentColor)
            Text("Music Only")
                .font(.system(
                    size: isCurrent ? activeSize : inactiveSize,
                    weight: isCurrent ? .bold : .semibold,
                    design: .rounded
                ))
                .italic()
                .foregroundColor(accentColor)
            Image(systemName: "guitars.fill")
                .font(.system(size: isCurrent ? activeSize - 3 : inactiveSize - 3, weight: .semibold))
                .foregroundColor(accentColor.opacity(0.85))
        }
        .shadow(color: isCurrent ? Color.white.opacity(0.65) : .clear, radius: 1, x: 0, y: 0.5)
    }

    private var annotatedView: some View {
        let rows = buildRows(from: line.annotations, maxCharsPerRow: isCompact ? 14 : 18)
        let phoneticActiveSize: CGFloat = round((isCompact ? 9 : 11) * sizeScale)
        let phoneticInactiveSize: CGFloat = round((isCompact ? 8 : 9) * sizeScale)
        let charActiveSize: CGFloat = round((isCompact ? 15.5 : 18.5) * sizeScale)
        let charInactiveSize: CGFloat = round((isCompact ? 12.5 : 14.5) * sizeScale)

        return VStack(spacing: isCompact ? 2 : 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        if item.character == " " {
                            Spacer().frame(width: isCompact ? 5 : 7)
                        } else {
                            VStack(spacing: 0) {
                                Text(item.phonetic)
                                    .font(.system(
                                        size: isCurrent ? phoneticActiveSize : phoneticInactiveSize,
                                        weight: .bold,
                                        design: .rounded
                                    ))
                                    .foregroundColor(phoneticColor)
                                    .lineLimit(1)
                                    .fixedSize()

                                Text(item.character)
                                    .font(.system(
                                        size: isCurrent ? charActiveSize : charInactiveSize,
                                        weight: isCurrent ? .bold : .semibold,
                                        design: .rounded
                                    ))
                                    .foregroundColor(textColor)
                                    .shadow(color: isCurrent ? Color.white.opacity(0.65) : .clear, radius: 1, x: 0, y: 0.5)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }

    private func buildRows(from chars: [AnnotatedChar], maxCharsPerRow: Int) -> [[AnnotatedChar]] {
        var rows: [[AnnotatedChar]] = []
        var currentRow: [AnnotatedChar] = []
        var charBudget = 0

        for item in chars {
            let weight = max(1, item.character.count)
            currentRow.append(item)
            charBudget += weight

            if charBudget >= maxCharsPerRow && (item.character == " " || item.phonetic.isEmpty || item.character.count == 1) {
                rows.append(currentRow)
                currentRow = []
                charBudget = 0
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }

    private var textColor: Color {
        if isCurrent {
            return Color.black.opacity(0.95)
        } else if isPast {
            return Color.black.opacity(0.50)
        } else {
            return Color.black.opacity(0.68)
        }
    }

    private var phoneticColor: Color {
        if isCurrent {
            return Color(red: 0.04, green: 0.34, blue: 0.78)
        } else if isPast {
            return Color(red: 0.04, green: 0.34, blue: 0.78).opacity(0.50)
        } else {
            return Color(red: 0.04, green: 0.34, blue: 0.78).opacity(0.70)
        }
    }

    private var lineOpacity: Double {
        if isCurrent { return 1.0 }
        switch distance {
        case 1: return 0.82
        case 2: return 0.60
        case 3: return 0.42
        default: return 0.28
        }
    }

    private var blurRadius: CGFloat {
        if isCurrent { return 0 }
        switch distance {
        case 1: return 0
        case 2: return 0.35
        default: return 0.9
        }
    }
}
