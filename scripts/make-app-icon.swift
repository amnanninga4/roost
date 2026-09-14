#!/usr/bin/env swift
//
// Draws Roost's placeholder app icon and writes it into the asset catalog:
//
//     swift scripts/make-app-icon.swift
//
// The icon is a placeholder. App Store Connect refuses a build with no 1024x1024 icon, so the app
// needs one before anything can reach TestFlight; what Anne and Wes actually want it to look like is
// D-7 and lands in the same slot. Keeping it generated rather than dropped in as a binary means the
// mark is readable and editable here instead of only in the PNG.
//
// Two things App Store Connect checks that are easy to get wrong:
//
//   * No alpha. The 1024 icon is rejected if it carries an alpha channel, so the bitmap is
//     `noneSkipLast` — 32 bits per pixel with the fourth byte ignored — and ImageIO writes it out as
//     8-bit RGB.
//   * No rounded corners. iOS applies the superellipse mask itself; baking one in leaves a dark
//     fringe. The canvas is filled corner to corner and the mark stays inside the middle 80%.
//
// Rasterisation is CoreGraphics', so the output is byte-identical from run to run on one machine but
// is not promised to be across macOS versions. The PNG is committed; regenerate it deliberately.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-app-icon: \(message)\n".utf8))
    exit(1)
}

// MARK: - The canvas

/// What App Store Connect asks for. iOS derives every smaller size from it.
let side = 1024.0

/// `RoostColor.accentToken` light — Packages/RoostDesign/Sources/RoostDesign/RoostColor.swift.
let accent = (r: 0x2F / 255.0, g: 0x8F / 255.0, b: 0x72 / 255.0)

// MARK: - The mark

// A perch with something at rest on it. The two shapes overlap by ten points so they fill as one
// silhouette rather than meeting at a tangent, which goes ragged at Home Screen sizes.

/// The perch: a stadium, wider than the body so the mark sits rather than balances.
let perchWidth = 560.0
let perchHeight = 60.0
let perchTop = 592.0

/// What sits on it.
let bodyRadius = 120.0
let bodyCenterY = 482.0

// The union spans y 362...652 and x 232...792 — its middle is a few points above the canvas's, which
// is where the eye reads centre, and every edge is more than 200 points clear of the corner mask.

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("could not make an sRGB color space")
}

guard let context = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: Int(side) * 4,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fail("could not make a \(Int(side))x\(Int(side)) opaque bitmap context")
}

// Flip so the geometry above reads top-down, the way the design does.
context.translateBy(x: 0, y: side)
context.scaleBy(x: 1, y: -1)

context.setFillColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: side, height: side))

// Filled as two shapes, not one path: nonzero winding would punch a hole where they overlap if the
// ellipse and the rounded rectangle wound in opposite directions.
context.setFillColor(gray: 1, alpha: 1)

let perch = CGPath(
    roundedRect: CGRect(x: (side - perchWidth) / 2, y: perchTop, width: perchWidth, height: perchHeight),
    cornerWidth: perchHeight / 2,
    cornerHeight: perchHeight / 2,
    transform: nil
)
context.addPath(perch)
context.fillPath()

context.fillEllipse(in: CGRect(
    x: side / 2 - bodyRadius,
    y: bodyCenterY - bodyRadius,
    width: bodyRadius * 2,
    height: bodyRadius * 2
))

// MARK: - Write it

let iconSet = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Roost/Resources/Assets.xcassets/AppIcon.appiconset")
let output = iconSet.appendingPathComponent("AppIcon.png")

do {
    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
} catch {
    fail("could not make \(iconSet.path): \(error.localizedDescription)")
}

guard let image = context.makeImage() else {
    fail("could not read the bitmap back out of the context")
}

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fail("could not open \(output.path) for writing")
}

CGImageDestinationAddImage(destination, image, nil)

guard CGImageDestinationFinalize(destination) else {
    fail("could not write \(output.path)")
}

print("wrote \(output.path) — \(image.width)x\(image.height)")
