import AppKit

@main
struct NyanyiApp {
    static func main() {
        // Ensure only a single instance of Nyanyi is running at any time
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "id.arkrwn.nyanyi"
        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier != currentPID &&
               (app.bundleIdentifier == bundleID || app.localizedName == "Nyanyi") {
                app.forceTerminate()
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
