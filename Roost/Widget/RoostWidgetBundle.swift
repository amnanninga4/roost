// The extension's entry point. One widget for now.
//
// The extension is its own process, so RoostDesign's fonts have to be registered here as well as in the
// app — `RoostFonts.register()` is per-process and idempotent. Without it every rung falls back to the
// system face, which is legible but is not Roost.
import RoostDesign
import SwiftUI
import WidgetKit

@main
struct RoostWidgetBundle: WidgetBundle {
    init() {
        try? RoostFonts.register()
    }

    var body: some Widget {
        TodayWidget()
    }
}
