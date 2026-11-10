import XCTest
@testable import KCNA26Core

/// The colour values ported from theme/Color.kt.
final class PaletteTests: XCTestCase {

    func testCategoryMapsAreInWebOrder() {
        let order = ["key", "talk", "mnt", "hands", "show", "com", "soc", "colo", "log"]
        XCTAssertEqual(CategoryLight.keys, order)
        XCTAssertEqual(CategoryDark.keys, order)
        XCTAssertEqual(TestData.repo.categories.keys, order)
        XCTAssertEqual(CategoryLight["key"], 0xFFC2_255B)
        XCTAssertEqual(CategoryDark["log"], 0xFF6F_7C86)
    }

    func testRoles() {
        let l = AppPalette.light, d = AppPalette.dark
        XCTAssertFalse(l.isDark)
        XCTAssertTrue(d.isDark)
        XCTAssertEqual(l.bg, 0xFFF1_F2EE)
        XCTAssertEqual(d.surface, 0xFF15_202A)
        XCTAssertEqual(l.you, l.pink)
        XCTAssertEqual(d.anthropic, d.clay)
        XCTAssertEqual(l.onYou, 0xFFFF_FFFF)
        XCTAssertEqual(l.category("nope"), l.muted)
        XCTAssertEqual(l.mapMe, CategoryLight["talk"])
        XCTAssertEqual(d.note, CategoryDark["hands"])
        XCTAssertEqual(l.scrim, 0x7308_0E14)
        XCTAssertEqual(AppPalette.forDark(true), d)
        // The theme agrees with schedule.json's own category colours.
        for (k, c) in TestData.repo.categories {
            XCTAssertEqual(try c.argb(dark: false), l.category(k), k)
            XCTAssertEqual(try c.argb(dark: true), d.category(k), k)
        }
    }

    func testDerivedColoursMatchComposeMaths() {
        // Expected values: Compose's Float channel maths (color-mix per channel, then
        // (x * 255 + 0.5).toInt()), computed with IEEE single precision.
        let l = AppPalette.light, d = AppPalette.dark
        XCTAssertEqual(l.liveBorder, 0xFFCC_7893)
        XCTAssertEqual(l.anthropicCardBg, 0xFFF9_F0EC)
        XCTAssertEqual(l.anthropicCardBorder, 0xFFCB_A18C)
        XCTAssertEqual(l.anthropicRowBg, 0x1AB9_572F)
        XCTAssertEqual(l.pressed, 0x0F13_202A)
        XCTAssertEqual(l.mapHyatt, 0xFFE2_E9F3)
        XCTAssertEqual(l.primaryContainer, 0xFFF6_E0E8)
        XCTAssertEqual(d.liveBorder, 0xFF8D_3C5E)
        XCTAssertEqual(d.anthropicCardBg, 0xFF27_2A2F)
        XCTAssertEqual(d.anthropicCardBorder, 0xFF79_594D)
        XCTAssertEqual(d.anthropicRowBg, 0x1AE0_8A62)
        XCTAssertEqual(d.pressed, 0x0FE6_EBEE)
        XCTAssertEqual(d.mapHyatt, 0xFF23_3345)
        XCTAssertEqual(d.primaryContainer, 0xFF32_2535)
        // Edge fractions are clamped.
        XCTAssertEqual(mixARGB(0xFF00_0000, 0xFFFF_FFFF, 2), 0xFF00_0000)
        XCTAssertEqual(mixARGB(0xFF00_0000, 0xFFFF_FFFF, -1), 0xFFFF_FFFF)
    }

    func testHexParsingAndComponents() throws {
        XCTAssertEqual(try parseHexColor("#C2255B"), 0xFFC2_255B)
        XCTAssertEqual(try parseHexColor("C2255B"), 0xFFC2_255B)
        XCTAssertEqual(try parseHexColor("#80C2255B"), 0x80C2_255B)
        // The same bits as Kotlin's (negative) Int.
        XCTAssertEqual(Int32(bitPattern: try parseHexColor("#C2255B")), -4_053_669)
        for bad in ["#C2255", "#GGGGGG", "", "#", "#C2255B00FF"] {
            XCTAssertThrowsError(try parseHexColor(bad), bad)
        }
        let c = argbComponents(0x80FF_0033)
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0.2, accuracy: 1e-9)
        XCTAssertEqual(c.alpha, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual("straße · 9:05 am".caps(), "STRASSE · 9:05 AM")
        XCTAssertEqual(Dimens.touchTarget, 48)
    }
}
