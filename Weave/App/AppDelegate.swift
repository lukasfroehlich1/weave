import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let app = GhosttyRuntime.shared.app {
            ghostty_app_set_focus(app, true)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if let app = GhosttyRuntime.shared.app {
            ghostty_app_set_focus(app, false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhosttyRuntime.shared.store?.saveScrollback()
    }
}
