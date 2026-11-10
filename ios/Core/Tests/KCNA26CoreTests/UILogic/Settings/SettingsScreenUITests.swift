import XCTest
@testable import KCNA26Core

/// Tests of the iOS-only end of the Settings list (UILogic/Settings/SettingsScreen+UI.swift):
/// credits, the bundled font licences and the app version line. No Kotlin counterpart.
final class SettingsScreenUITests: XCTestCase {
    /// ios/KCNA26/Resources/Licenses: copied into the app bundle as the "Licenses" folder.
    private let licensesDir: URL = TestData.dataDir
        .deletingLastPathComponent()
        .appendingPathComponent(SettingsScreenLogic.LICENSES_FOLDER, isDirectory: true)

    func testTheCreditsAreTheReadmes() throws {
        let readme = try String(contentsOf: TestData.repoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains(SettingsScreenLogic.DATA_CREDIT))
        XCTAssertTrue(readme.contains(SettingsScreenLogic.UNOFFICIAL))
        XCTAssertTrue(readme.contains("both under the SIL Open Font License 1.1"))
        XCTAssertEqual("Credits", SettingsScreenLogic.CREDITS)
        XCTAssertEqual("SIL Open Font License 1.1", SettingsScreenLogic.FONT_LICENSE_NAME)
    }

    func testEveryBundledFontHasItsLicenceText() throws {
        XCTAssertEqual(["Barlow Condensed", "Atkinson Hyperlegible"], SettingsScreenLogic.FONT_LICENSES.map(\.name))
        for license in SettingsScreenLogic.FONT_LICENSES {
            let text = try XCTUnwrap(SettingsScreenLogic.licenseText(license, inDirectory: licensesDir), license.file)
            XCTAssertTrue(text.hasPrefix("Copyright "), license.file)
            XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE Version 1.1"), license.file)
            // The same file the Android app ships.
            let android = TestData.androidAssetsDir.appendingPathComponent("licenses/\(license.file)")
            XCTAssertEqual(try Data(contentsOf: android), Data(text.utf8), license.file)
        }
        // Each licence names its own font.
        XCTAssertTrue(SettingsScreenLogic.licenseText(SettingsScreenLogic.FONT_LICENSES[0], inDirectory: licensesDir)!
            .contains("The Barlow Project Authors"))
        XCTAssertTrue(SettingsScreenLogic.licenseText(SettingsScreenLogic.FONT_LICENSES[1], inDirectory: licensesDir)!
            .contains("Braille Institute of America"))
        // The folder has nothing else to credit.
        let files = try FileManager.default.contentsOfDirectory(atPath: licensesDir.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(Set(SettingsScreenLogic.FONT_LICENSES.map(\.file)), Set(files))
    }

    func testAMissingLicenceIsNil() {
        let missing = SettingsScreenLogic.FontLicense(name: "Nope", file: "OFL-Nope.txt")
        XCTAssertNil(SettingsScreenLogic.licenseText(missing, inDirectory: licensesDir))
        XCTAssertNil(SettingsScreenLogic.licenseText(missing, in: Bundle(for: SettingsScreenUITests.self)))
    }

    func testTheLicenceRowLabel() {
        XCTAssertEqual(
            "Barlow Condensed, SIL Open Font License 1.1",
            SettingsScreenLogic.licenseRowLabel(SettingsScreenLogic.FONT_LICENSES[0])
        )
    }

    func testTheAppVersionLine() {
        XCTAssertEqual("App version 1.0 (12)", SettingsScreenLogic.appVersion("1.0", "12"))
        XCTAssertEqual("App version 1.0", SettingsScreenLogic.appVersion("1.0", "1.0"))
        XCTAssertEqual("App version 1.0", SettingsScreenLogic.appVersion(" 1.0 ", nil))
        XCTAssertEqual("App version 1.0", SettingsScreenLogic.appVersion("1.0", "  "))
        XCTAssertEqual("App version 12", SettingsScreenLogic.appVersion(nil, "12"))
        XCTAssertEqual("App version 12", SettingsScreenLogic.appVersion("", "12"))
        XCTAssertNil(SettingsScreenLogic.appVersion(nil, nil))
        XCTAssertNil(SettingsScreenLogic.appVersion(" ", ""))
        // A test bundle has no app version keys of its own on Linux; whatever it has, no crash.
        _ = SettingsScreenLogic.appVersion(from: Bundle(for: SettingsScreenUITests.self))
    }
}
