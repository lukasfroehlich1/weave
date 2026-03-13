import Sparkle

final class Updater: NSObject, SPUUpdaterDelegate {
    private static let baseFeedURL = "https://github.com/lukasfroehlich1/weave/releases/download"
    private static let stableFeed = "\(baseFeedURL)/appcast/appcast.xml"
    private static let betaFeed = "\(baseFeedURL)/appcast/appcast-beta.xml"

    private var updater: SPUUpdater?

    var betaUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: "betaUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "betaUpdates") }
    }

    override init() {
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updater = controller.updater
    }

    func start() {
        try? updater?.start()
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        betaUpdates ? Self.betaFeed : Self.stableFeed
    }
}
