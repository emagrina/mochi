#!/usr/bin/env swift
// Generates Resources/AppIcon.iconset/*.png from code — no external art tools, no bitmap
// assets checked in by hand. Run via `swift Scripts/generate-app-icon.swift`, then
// `iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns`.
//
// The icon mirrors MochiAvatar's neutral/happy face: a soft rounded-square "rice cake" body,
// a simple closed-smile face, one small warm accent dot. Deliberately plain at icon scale —
// no provider accessory, no status tinting (product spec section 32: minimal, not overly
// detailed, not just an emoji dropped into a square).

import AppKit

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2)
]

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bodyInset = size * 0.08
    let bodyRect = NSRect(x: bodyInset, y: bodyInset, width: size - bodyInset * 2, height: size - bodyInset * 2)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: size * 0.40, yRadius: size * 0.40)

    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    bodyPath.fill()

    // Soft top-left highlight.
    let highlight = NSBezierPath(ovalIn: NSRect(x: size * 0.22, y: size * 0.60, width: size * 0.30, height: size * 0.16))
    NSColor(calibratedWhite: 1.0, alpha: 0.5).setFill()
    highlight.fill()

    // Warm accent dot (Mochi's own identity, not tied to any provider).
    let accent = NSBezierPath(ovalIn: NSRect(x: size * 0.70, y: size * 0.72, width: size * 0.12, height: size * 0.12))
    NSColor(calibratedRed: 0.80, green: 0.42, blue: 0.27, alpha: 1).setFill()
    accent.fill()

    let face = NSColor(calibratedWhite: 0.15, alpha: 1)

    // Eyes: two simple dots.
    for dx: CGFloat in [-0.14, 0.14] {
        let eye = NSBezierPath(ovalIn: NSRect(x: size * (0.5 + dx) - size * 0.045, y: size * 0.47, width: size * 0.09, height: size * 0.09))
        face.setFill()
        eye.fill()
    }

    // Mouth: upward smile arc.
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: size * 0.40, y: size * 0.36))
    mouth.curve(
        to: NSPoint(x: size * 0.60, y: size * 0.36),
        controlPoint1: NSPoint(x: size * 0.46, y: size * 0.28),
        controlPoint2: NSPoint(x: size * 0.54, y: size * 0.28)
    )
    mouth.lineWidth = size * 0.028
    mouth.lineCapStyle = .round
    face.setStroke()
    mouth.stroke()

    image.unlockFocus()
    return image
}

let fm = FileManager.default
let outputDir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

for entry in sizes {
    let pixelSize = entry.points * entry.scale
    let image = draw(size: pixelSize)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Failed to render \(entry.name)\n".utf8))
        continue
    }
    let url = outputDir.appendingPathComponent("\(entry.name).png")
    try png.write(to: url)
    print("Wrote \(url.path)")
}
