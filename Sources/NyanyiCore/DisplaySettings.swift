import Foundation
import Combine

public enum DisplayMode: String, CaseIterable {
    case floating = "floating"
    case corner = "corner"
    case subtitle = "subtitle"
    case menuBar = "menubar"

    public var label: String {
        switch self {
        case .floating: return "Floating Card"
        case .corner: return "Corner Card"
        case .subtitle: return "Subtitle (Movie Style)"
        case .menuBar: return "Menu Bar Ticker"
        }
    }

    public var isSubtitleStyle: Bool {
        self == .subtitle
    }
}

public enum OverlaySize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    public var scaleFactor: Double {
        switch self {
        case .small: return 0.82
        case .medium: return 1.0
        case .large: return 1.25
        }
    }
}

public enum CornerPosition: String, CaseIterable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
}

public final class DisplaySettings: ObservableObject {
    @Published public var mode: DisplayMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "displayMode") }
    }
    @Published public var size: OverlaySize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: "overlaySize") }
    }
    @Published public var corner: CornerPosition {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "cornerPosition") }
    }

    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? ""
        // Migrate legacy "subtitleBottom" / "subtitleTop" saved values seamlessly to `.subtitle`
        if savedMode == "subtitleBottom" || savedMode == "subtitleTop" {
            self.mode = .subtitle
        } else {
            self.mode = DisplayMode(rawValue: savedMode) ?? .floating
        }

        let savedSize = UserDefaults.standard.string(forKey: "overlaySize") ?? ""
        self.size = OverlaySize(rawValue: savedSize) ?? .medium

        let savedCorner = UserDefaults.standard.string(forKey: "cornerPosition") ?? ""
        self.corner = CornerPosition(rawValue: savedCorner) ?? .bottomRight
    }
}
