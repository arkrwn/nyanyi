import Foundation
import Combine

public enum DisplayMode: String, CaseIterable {
    case floating = "floating"
    case corner = "corner"
    case menuBar = "menubar"

    public var label: String {
        switch self {
        case .floating: return "Floating"
        case .corner: return "Corner"
        case .menuBar: return "Menu Bar"
        }
    }
}

public enum PlayerSourcePreference: String, CaseIterable {
    case auto = "auto"
    case spotify = "spotify"
    case youtubeMusic = "ytmusic"

    public var label: String {
        switch self {
        case .auto: return "Auto (Spotify + YouTube Music)"
        case .spotify: return "Spotify Only"
        case .youtubeMusic: return "YouTube Music Only"
        }
    }
}

public enum PhoneticMode: String, CaseIterable {
    case autoNonLatin = "auto"
    case allScripts = "all"
    case off = "off"

    public var label: String {
        switch self {
        case .autoNonLatin: return "Auto (Non-Latin -> Latin)"
        case .allScripts: return "All Scripts"
        case .off: return "Off"
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
    @Published public var corner: CornerPosition {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "cornerPosition") }
    }
    @Published public var sourcePreference: PlayerSourcePreference {
        didSet { UserDefaults.standard.set(sourcePreference.rawValue, forKey: "sourcePreference") }
    }
    @Published public var phoneticMode: PhoneticMode {
        didSet { UserDefaults.standard.set(phoneticMode.rawValue, forKey: "phoneticMode") }
    }

    public init() {
        let savedMode = UserDefaults.standard.string(forKey: "displayMode") ?? ""
        self.mode = DisplayMode(rawValue: savedMode) ?? .floating

        let savedCorner = UserDefaults.standard.string(forKey: "cornerPosition") ?? ""
        self.corner = CornerPosition(rawValue: savedCorner) ?? .bottomRight

        let savedSource = UserDefaults.standard.string(forKey: "sourcePreference") ?? ""
        self.sourcePreference = PlayerSourcePreference(rawValue: savedSource) ?? .auto

        let savedPhonetic = UserDefaults.standard.string(forKey: "phoneticMode") ?? ""
        self.phoneticMode = PhoneticMode(rawValue: savedPhonetic) ?? .autoNonLatin
    }
}
