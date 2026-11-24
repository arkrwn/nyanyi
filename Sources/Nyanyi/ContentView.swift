import SwiftUI
import AppKit
import NyanyiCore

// MARK: - Native AppKit Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Main Overlay Content View

struct ContentView: View {
    @ObservedObject var viewModel: LyricsViewModel
    @ObservedObject var displaySettings: DisplaySettings

    private var isCompact: Bool { displaySettings.mode == .corner }

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(spacing: 0) {
                headerBar
                if viewModel.lines.isEmpty {
                    emptyStateView
                } else {
                    lyricsScrollView
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(viewModel.isHovering ? 0.18 : 0.08), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.isHovering = hovering
            }
        }
    }

    // MARK: - Track Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isPlaying ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)

            if !viewModel.trackTitle.isEmpty {
                Text(viewModel.trackTitle)
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                if !viewModel.artist.isEmpty {
                    Text("- \(viewModel.artist)")
                        .font(.system(size: isCompact ? 10 : 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            } else {
                Text("Nyanyi")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if !viewModel.activeSourceName.isEmpty {
                Text(shortSourceBadge(viewModel.activeSourceName))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.top, isCompact ? 8 : 12)
        .padding(.bottom, isCompact ? 5 : 8)
    }

    private func shortSourceBadge(_ sourceName: String) -> String {
        if sourceName.hasPrefix("YouTube Music") {
            return "YT Music"
        }
        return sourceName
    }

    // MARK: - Scrollable Synced Lyrics

    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: isCompact ? 6 : 10) {
                    Spacer().frame(height: isCompact ? 16 : 36)

                    ForEach(Array(viewModel.lines.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(
                            line: line,
                            isCurrent: index == viewModel.currentLineIndex,
                            isPast: isPastLine(index),
                            distance: lineDistance(index),
                            isCompact: isCompact
                        )
                        .id(index)
                    }

                    Spacer().frame(height: isCompact ? 36 : 80)
                }
                .padding(.horizontal, isCompact ? 12 : 16)
            }
            .onChange(of: viewModel.currentLineIndex) { newIndex in
                guard let idx = newIndex else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
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
                    .scaleEffect(0.8)
                    .colorScheme(.dark)
                Text("Searching lyrics...")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            } else if viewModel.trackTitle.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.3))
                Text("Play a song on Spotify or YouTube Music")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            } else {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.3))
                Text("No lyrics found")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
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

// MARK: - Single Lyric Line View

struct LyricLineView: View {
    let line: LyricLine
    let isCurrent: Bool
    let isPast: Bool
    let distance: Int
    var isCompact: Bool = false

    var body: some View {
        Group {
            if line.hasPhonetics {
                annotatedView
            } else {
                plainView
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, isCurrent ? (isCompact ? 2 : 4) : 1)
        .scaleEffect(isCurrent ? 1.03 : 0.96)
        .opacity(lineOpacity)
        .blur(radius: blurRadius)
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
        .animation(.easeInOut(duration: 0.3), value: distance)
    }

    private var plainView: some View {
        let activeSize: CGFloat = isCompact ? 15 : 18
        let inactiveSize: CGFloat = isCompact ? 12 : 15
        return Text(line.text)
            .font(.system(
                size: isCurrent ? activeSize : inactiveSize,
                weight: isCurrent ? .bold : .medium,
                design: .rounded
            ))
            .foregroundColor(textColor)
            .multilineTextAlignment(.center)
            .shadow(color: isCurrent ? .black.opacity(0.5) : .clear, radius: 3, y: 1)
    }

    private var annotatedView: some View {
        let rows = buildRows(from: line.annotations, maxCharsPerRow: isCompact ? 14 : 18)
        let phoneticActiveSize: CGFloat = isCompact ? 8 : 10
        let phoneticInactiveSize: CGFloat = isCompact ? 7 : 8
        let charActiveSize: CGFloat = isCompact ? 15 : 18
        let charInactiveSize: CGFloat = isCompact ? 12 : 14

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
                                        weight: .medium,
                                        design: .rounded
                                    ))
                                    .foregroundColor(phoneticColor)
                                    .lineLimit(1)
                                    .fixedSize()

                                Text(item.character)
                                    .font(.system(
                                        size: isCurrent ? charActiveSize : charInactiveSize,
                                        weight: isCurrent ? .bold : .medium
                                    ))
                                    .foregroundColor(textColor)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .shadow(color: isCurrent ? .black.opacity(0.5) : .clear, radius: 3, y: 1)
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
            return .white
        } else if isPast {
            return .white.opacity(0.4)
        } else {
            return .white.opacity(0.6)
        }
    }

    private var phoneticColor: Color {
        if isCurrent {
            return Color(red: 0.55, green: 0.85, blue: 1.0)
        } else if isPast {
            return .white.opacity(0.3)
        } else {
            return .white.opacity(0.45)
        }
    }

    private var lineOpacity: Double {
        if isCurrent { return 1.0 }
        switch distance {
        case 1: return 0.7
        case 2: return 0.45
        case 3: return 0.28
        default: return 0.15
        }
    }

    private var blurRadius: CGFloat {
        if isCurrent { return 0 }
        switch distance {
        case 1: return 0
        case 2: return 0.5
        default: return 1.5
        }
    }
}
