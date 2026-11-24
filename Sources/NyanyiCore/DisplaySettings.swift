import Foundation
import Combine

public enum DisplayMode: String, CaseIterable {
    case floating = "floating"
    case corner = "corner"
    case subtitleBottom = "subtitleBottom"
    case subtitleTop = "subtitleTop"
    case menuBar = "menubar"

    public var label: String {
        switch self {
        case .floating: return "Floating Card"
        case .corner: return "Corner Card"
        case .subtitleBottom: return "Bottom Subtitle (Movie Style)"
        case .subtitleTop: return "Top Subtitle (Movie Style)"
        case .menuBar: return "Menu Bar Ticker"
        }
    }

    public var isSubtitleStyle: Bool {
        self == .subtitleBottom || self == .subtitleTop
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
    @Published public var corner: CornerPosition {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "cornerPosition") }
    }

    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? ""
        self.mode = DisplayMode(rawValue: savedMode) ?? .floating

        let savedCorner = UserDefaults.standard.string(forKey: "cornerPosition") ?? ""
        self.corner = CornerPosition(rawValue: savedCorner) ?? .bottomRight
    }
}
