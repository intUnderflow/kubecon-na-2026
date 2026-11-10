import Foundation

/// Everything the platform gives the ``AppGraph`` (Android: the Application `Context`, its
/// assets, SharedPreferences and BuildConfig). The iOS app builds it with
/// ``live(reminders:notificationPermission:isDebug:bundle:log:)``; tests pass temporary
/// folders, in-memory stores and fakes.
struct AppServices: Sendable {
    /// The app's private, persistent folder (Android `filesDir`): Application Support. Holds
    /// `data/` (downloaded data sets, ``DataSync``) and `details/` (fetched session descriptions;
    /// not Caches: they must survive low-storage purges for offline use).
    var filesDirectory: URL
    /// The ``KeyValueStore`` for a prefs file name (`SettingsStore.PREFS`, `GoingStore.PREFS`,
    /// `ReminderStore.PREFS`, `FakeableClock.PREFS`, `DataSync.PREFS`). Called once per name.
    var prefs: @Sendable (_ name: String) -> any KeyValueStore
    /// Reads a bundled data file by name (``DataSync/bundledOpener(_:)``; Android `assets.open`).
    var bundledData: @Sendable (_ name: String) throws -> Data
    /// Live data updates (``HttpDataFetcher``).
    var dataFetcher: any DataFetcher
    /// Live session descriptions (``SessionizeFetcher``).
    var detailsFetcher: any DetailsFetcher
    /// Local notifications (`UNUserNotificationCenter`).
    var reminders: any ReminderScheduling
    /// Notification permission (`UNUserNotificationCenter`).
    var notificationPermission: any NotificationPermission
    /// Where the published data lives (``DataSync/baseUrl(from:)``; Android `BuildConfig.DATA_BASE_URL`).
    var dataBaseUrl: String
    /// `CFBundleVersion` (``DataSync/appVersion(from:)``; Android `VERSION_CODE`).
    var appVersion: Int
    /// Debug build (Android `BuildConfig.DEBUG`): enables the fake clock and `-fakeNow`.
    var isDebug: Bool
    /// The real wall clock (data sync timing, notification fire dates).
    var wallClock: any AppClock
    /// Tests only: replaces the app clock (otherwise the ``FakeableClock``).
    var clockOverride: (any AppClock)?
    /// Log lines (Android `Log.i(TAG, …)`): ``defaultLog`` prints "kcna26: …" in debug builds.
    var log: @Sendable (String) -> Void

    init(
        filesDirectory: URL,
        prefs: @escaping @Sendable (_ name: String) -> any KeyValueStore,
        bundledData: @escaping @Sendable (_ name: String) throws -> Data,
        dataFetcher: any DataFetcher,
        detailsFetcher: any DetailsFetcher,
        reminders: any ReminderScheduling,
        notificationPermission: any NotificationPermission,
        dataBaseUrl: String = DataSync.DEFAULT_BASE_URL,
        appVersion: Int = 0,
        isDebug: Bool = AppServices.isDebugBuild,
        wallClock: any AppClock = SystemAppClock.shared,
        clockOverride: (any AppClock)? = nil,
        log: @escaping @Sendable (String) -> Void = AppServices.defaultLog
    ) {
        self.filesDirectory = filesDirectory
        self.prefs = prefs
        self.bundledData = bundledData
        self.dataFetcher = dataFetcher
        self.detailsFetcher = detailsFetcher
        self.reminders = reminders
        self.notificationPermission = notificationPermission
        self.dataBaseUrl = dataBaseUrl
        self.appVersion = appVersion
        self.isDebug = isDebug
        self.wallClock = wallClock
        self.clockOverride = clockOverride
        self.log = log
    }

    /// The real app: Application Support (created if needed), `UserDefaults` suites named after
    /// the prefs files, the bundle's "Data" folder, URLSession fetchers, and the Info.plist's
    /// data base URL and build number. `reminders` and `notificationPermission` are the app
    /// layer's `UNUserNotificationCenter` implementations.
    static func live(
        reminders: any ReminderScheduling,
        notificationPermission: any NotificationPermission,
        isDebug: Bool = AppServices.isDebugBuild,
        bundle: Bundle = .main,
        log: @escaping @Sendable (String) -> Void = AppServices.defaultLog
    ) -> AppServices {
        let dir = applicationSupportDirectory()
        return AppServices(
            filesDirectory: dir,
            prefs: { name in UserDefaultsStore(suiteName: name) },
            bundledData: DataSync.bundledOpener(bundle),
            dataFetcher: HttpDataFetcher(),
            detailsFetcher: SessionizeFetcher(),
            reminders: reminders,
            notificationPermission: notificationPermission,
            dataBaseUrl: DataSync.baseUrl(from: bundle),
            appVersion: DataSync.appVersion(from: bundle),
            isDebug: isDebug,
            log: log
        )
    }

    /// `<Application Support>` (created if missing), else the temporary folder.
    static func applicationSupportDirectory(_ fm: FileManager = .default) -> URL {
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fm.temporaryDirectory
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// True when compiled with `DEBUG` (the app's Debug configuration).
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Prints "kcna26: <message>" in debug builds; silent in release builds.
    static let defaultLog: @Sendable (String) -> Void = { message in
        #if DEBUG
        print("\(KCNA_TAG): \(message)")
        #endif
    }

    /// Kotlin `KcnaApp.TAG`.
    static let KCNA_TAG = "kcna26"
}
