import Foundation
import Combine

public enum DisplayMode: String, CaseIterable {
    case floating = "floating"
    case corner = "corner"
    case subtitle = "subtitle"
    case bottomNavbar = "bottomNavbar"
    case menuBar = "menubar"

    public var label: String {
        switch self {
        case .floating: return "Floating Card"
        case .corner: return "Corner Card"
        case .subtitle: return "Subtitle (Movie Style)"
        case .bottomNavbar: return "Bottom Navbar (Apple Bar)"
        case .menuBar: return "Menu Bar Ticker"
        }
    }

    public var isSubtitleStyle: Bool {
        self == .subtitle
    }

    public var isBottomNavbar: Bool {
        self == .bottomNavbar
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

    /// Re-calibrated smaller, sleeker scale factors so Small is genuinely compact
    public var scaleFactor: Double {
        switch self {
        case .small: return 0.65
        case .medium: return 0.82
        case .large: return 1.0
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
    @Published public var bottomNavbarAutoHide: Bool {
        didSet { UserDefaults.standard.set(bottomNavbarAutoHide, forKey: "bottomNavbarAutoHide") }
    }

    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? ""
        if savedMode == "subtitleBottom" || savedMode == "subtitleTop" {
            self.mode = .subtitle
        } else {
            self.mode = DisplayMode(rawValue: savedMode) ?? .floating
        }

        let savedSize = UserDefaults.standard.string(forKey: "overlaySize") ?? ""
        self.size = OverlaySize(rawValue: savedSize) ?? .medium

        let savedCorner = UserDefaults.standard.string(forKey: "cornerPosition") ?? ""
        self.corner = CornerPosition(rawValue: savedCorner) ?? .bottomRight

        if UserDefaults.standard.object(forKey: "bottomNavbarAutoHide") != nil {
            self.bottomNavbarAutoHide = UserDefaults.standard.bool(forKey: "bottomNavbarAutoHide")
        } else {
            self.bottomNavbarAutoHide = false
        }
    }
}
