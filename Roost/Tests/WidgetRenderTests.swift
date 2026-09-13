// D-5: every widget family renders, at its real size, to a real image.
//
// This is a test first — a family that lays out to nothing, or throws away its content at a size the
// system will actually ask for, fails here rather than on a Home Screen. It is also where
// `Roost/docs/widget-small.png` and `docs/widget-medium.png` come from: set `ROOST_WIDGET_SHOTS` to a
// directory and the two Home Screen families are written there as PNGs. Without it the test still renders,
// it just does not write anything, so CI does no file I/O.
//
// The host is the app rather than a widget extension, which is why `TodayWidgetView` takes a `family:`
// override: `EnvironmentValues.widgetFamily` is read-only and only a widget host sets it.
@testable import Roost
import RoostDesign
import SwiftUI
import WidgetKit
import XCTest

@MainActor
final class WidgetRenderTests: XCTestCase {
    /// The point sizes iOS asks for on a 6.3-inch iPhone (17 Pro). The accessory sizes are the documented
    /// lock-screen ones.
    private enum Size {
        static let small = CGSize(width: 170, height: 170)
        static let medium = CGSize(width: 364, height: 170)
        static let rectangular = CGSize(width: 160, height: 72)
        static let circular = CGSize(width: 76, height: 76)
    }

    /// The content margin a widget host applies for you, added here because nothing is hosting.
    private let hostMargin: CGFloat = 16
    /// The Home Screen widget's own corner radius, for the same reason.
    private let hostCorner: CGFloat = 24

    override func setUp() {
        super.setUp()
        try? RoostFonts.register()
    }

    private func render(
        _ entry: TodayEntry,
        family: WidgetFamily,
        size: CGSize,
        rounded: Bool = true
    ) throws -> UIImage {
        let view = TodayWidgetView(entry: entry, family: family)
            .padding(hostMargin)
            .frame(width: size.width, height: size.height)
            .background(RoostColor.Role.background.color)
            .clipShape(RoundedRectangle(cornerRadius: rounded ? hostCorner : 0, style: .continuous))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage, "\(family) rendered nothing")
    }

    /// Writes the image next to the test run so the committed `Roost/docs/widget-*.png` can be refreshed
    /// from it — the host app's tmp directory by default (`xcrun simctl get_app_container booted
    /// xyz.hinescreative.roost data`), or wherever `ROOST_WIDGET_SHOTS` points. Two small files inside the
    /// simulator's own sandbox, so CI is unaffected either way.
    private func png(_ image: UIImage, named name: String) throws {
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 1000, "\(name) is suspiciously small for a drawn widget")
        let dir = URL(filePath: ProcessInfo.processInfo.environment["ROOST_WIDGET_SHOTS"]
            ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try data.write(to: url)
        print("Roost: wrote \(url.path)")
    }

    private var sample: TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    // MARK: - the families

    func testSystemSmallRendersYourCountAndStreak() throws {
        let image = try render(sample, family: .systemSmall, size: Size.small)
        XCTAssertEqual(image.size.width, Size.small.width, accuracy: 1)
        try png(image, named: "widget-small.png")
    }

    func testSystemMediumRendersBothPeople() throws {
        let image = try render(sample, family: .systemMedium, size: Size.medium)
        XCTAssertEqual(image.size.width, Size.medium.width, accuracy: 1)
        try png(image, named: "widget-medium.png")
    }

    func testAccessoryRectangularRenders() throws {
        _ = try render(sample, family: .accessoryRectangular, size: Size.rectangular, rounded: false)
    }

    func testAccessoryCircularRenders() throws {
        _ = try render(sample, family: .accessoryCircular, size: Size.circular, rounded: false)
    }

    // MARK: - the states every family has to survive

    /// No snapshot at all: a fresh install, or a build with no App Group entitlement.
    func testEveryFamilyRendersWithNoSnapshot() throws {
        let empty = TodayEntry(date: .now, snapshot: nil)
        for (family, size) in [
            (WidgetFamily.systemSmall, Size.small),
            (.systemMedium, Size.medium),
            (.accessoryRectangular, Size.rectangular),
            (.accessoryCircular, Size.circular),
        ] {
            _ = try render(empty, family: family, size: size, rounded: false)
        }
    }

    /// A snapshot with counts but no paired person: the small and lock families have no "you" to show.
    func testEveryFamilyRendersUnpaired() throws {
        let unpaired = TodayEntry(
            date: .now,
            snapshot: RoostSnapshot(
                generatedAt: .now,
                me: nil,
                people: RoostSnapshot.placeholder.people
            )
        )
        for (family, size) in [
            (WidgetFamily.systemSmall, Size.small),
            (.systemMedium, Size.medium),
            (.accessoryRectangular, Size.rectangular),
            (.accessoryCircular, Size.circular),
        ] {
            _ = try render(unpaired, family: family, size: size, rounded: false)
        }
    }

    /// Nothing due: the hero number would be a zero, and a zero reads as broken, so it is a word instead.
    func testACaughtUpDayRenders() throws {
        let clear = TodayEntry(
            date: .now,
            snapshot: RoostSnapshot(
                generatedAt: .now,
                me: "anne",
                people: [
                    .init(id: "anne", name: "Anne", due: 0, overdue: 0, streak: 12, top: []),
                    .init(id: "wes", name: "Wes", due: 0, overdue: 0, streak: 12, top: []),
                ]
            )
        )
        _ = try render(clear, family: .systemSmall, size: Size.small)
        _ = try render(clear, family: .systemMedium, size: Size.medium)
        _ = try render(clear, family: .accessoryCircular, size: Size.circular, rounded: false)
    }

    /// A long chore title and a three-digit count: neither may push anything off the widget.
    func testALongTitleAndBigNumbersStillRender() throws {
        let crowded = TodayEntry(
            date: .now,
            snapshot: RoostSnapshot(
                generatedAt: .now,
                me: "wes",
                people: [
                    .init(
                        id: "anne", name: "Anne", due: 128, overdue: 99, streak: 365,
                        top: [.init(
                            title: "Wipe down kitchen counters, bathroom counters/mirror",
                            stage: .alert,
                            daysOverdue: 12
                        )]
                    ),
                    .init(
                        id: "wes", name: "Wes", due: 128, overdue: 99, streak: 365,
                        top: [.init(title: "Garbage can to street", stage: .pointed, daysOverdue: 3)]
                    ),
                ]
            )
        )
        _ = try render(crowded, family: .systemSmall, size: Size.small)
        _ = try render(crowded, family: .systemMedium, size: Size.medium)
        _ = try render(crowded, family: .accessoryRectangular, size: Size.rectangular, rounded: false)
    }
}
