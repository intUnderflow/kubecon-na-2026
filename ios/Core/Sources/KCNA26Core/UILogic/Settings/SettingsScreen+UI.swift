import Foundation

/// iOS additions to the Settings list, after ``SettingsScreenLogic/THEME_NOTE``. No Kotlin
/// counterpart: the Android app ships the same font licences in `assets/licenses` and states the
/// credits in the README, without a screen for them; an App Store app shows them in the app.
///
/// The section: ``CREDITS`` (a heading), ``DATA_CREDIT``, one row per ``FONT_LICENSES`` entry
/// (the font's name over ``FONT_LICENSE_NAME``; tapping it shows the bundled licence text,
/// ``licenseText(_:in:)``), ``UNOFFICIAL``, then ``appVersion(_:_:)``. The texts are the
/// README's "Credits" section, verbatim.
extension SettingsScreenLogic {
    /// The section heading ("CREDITS" in caps).
    static let CREDITS = "Credits"

    /// README "Credits", first point.
    static let DATA_CREDIT = "Schedule data comes from the official KubeCon + CloudNativeCon North America 2026 " +
        "and CNCF agendas via Sessionize. Session descriptions and speaker taglines are written by the speakers."

    /// README "Credits", closing line.
    static let UNOFFICIAL = "This is an unofficial community app. It is not affiliated with or endorsed by " +
        "the CNCF, the Linux Foundation or Anthropic."

    /// The licence of both bundled font families (the subtitle of their rows).
    static let FONT_LICENSE_NAME = "SIL Open Font License 1.1"

    /// The app bundle's folder of licence texts (ios/KCNA26/Resources/Licenses, copied as a folder).
    static let LICENSES_FOLDER = "Licenses"

    /// A bundled font family and the file of its licence text in ``LICENSES_FOLDER``.
    struct FontLicense: Sendable, Hashable {
        /// "Barlow Condensed".
        let name: String
        /// "OFL-BarlowCondensed.txt".
        let file: String
    }

    /// The fonts the app bundles (Resources/Fonts), in the README's order.
    static let FONT_LICENSES: [FontLicense] = [
        FontLicense(name: "Barlow Condensed", file: "OFL-BarlowCondensed.txt"),
        FontLicense(name: "Atkinson Hyperlegible", file: "OFL-AtkinsonHyperlegible.txt"),
    ]

    /// VoiceOver label of a licence row: "Barlow Condensed, SIL Open Font License 1.1".
    static func licenseRowLabel(_ license: FontLicense) -> String { "\(license.name), \(FONT_LICENSE_NAME)" }

    /// The licence text bundled with the app (`<bundle>/Licenses/<file>`), nil if it is missing.
    static func licenseText(_ license: FontLicense, in bundle: Bundle = .main) -> String? {
        guard let dir = bundle.resourceURL?.appendingPathComponent(LICENSES_FOLDER, isDirectory: true) else { return nil }
        return licenseText(license, inDirectory: dir)
    }

    /// The licence text in `dir` (the bundle's Licenses folder, or the source folder in tests).
    static func licenseText(_ license: FontLicense, inDirectory dir: URL) -> String? {
        let url = dir.appendingPathComponent(license.file, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// "App version 1.0 (12)" from `CFBundleShortVersionString` and `CFBundleVersion` (Android's
    /// versionName and versionCode); "App version 1.0" when the build is missing or the same,
    /// "App version 12" with only a build; nil with neither.
    static func appVersion(_ shortVersion: String?, _ build: String?) -> String? {
        let name = shortVersion?.kotlinTrim().takeIfNotBlank()
        let code = build?.kotlinTrim().takeIfNotBlank()
        switch (name, code) {
        case let (n?, c?):
            return kotlinEquals(n, c) ? "App version \(n)" : "App version \(n) (\(c))"
        case let (n?, nil):
            return "App version \(n)"
        case let (nil, c?):
            return "App version \(c)"
        case (nil, nil):
            return nil
        }
    }

    /// ``appVersion(_:_:)`` of `bundle`'s Info.plist.
    static func appVersion(from bundle: Bundle) -> String? {
        appVersion(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
