#!/usr/bin/env swift
// Generates every derivative visual asset Mochi ships from the two checked-in, high-resolution
// source images under Resources/DesignSources/ — no bitmap assets produced by hand, no
// hardcoded pixel offsets tied to one specific export of the artwork, so this keeps working if
// the source images are ever re-exported at a different resolution.
//
// Run via `swift Scripts/generate-assets.swift` (Scripts/build-app.sh does this automatically
// whenever a generated asset is missing — see that script for the full pipeline, including
// `iconutil` turning Resources/AppIcon.iconset/ into Resources/AppIcon.icns).
//
// Produces:
//   Resources/AppIcon.iconset/*.png           — the macOS app icon, every required size
//   Sources/MochiApp/Resources/MochiMenuBarTemplate.png — the menu bar template image
//
// Both are derived by finding the actual artwork's bounding box in its source image (rather
// than assuming where it sits) and cropping a tightly-padded frame around it — never by
// stretching a small image up to a larger size. See `cropFrame(for:fillRatio:)`.

import AppKit
import CoreGraphics

let fm = FileManager.default
let rootDir = URL(fileURLWithPath: fm.currentDirectoryPath)
let designSourcesDir = rootDir.appendingPathComponent("Resources/DesignSources")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadCGImage(_ url: URL) -> CGImage {
    guard let data = try? Data(contentsOf: url),
          let provider = CGDataProvider(data: data as CFData),
          let source = CGImageSourceCreateWithDataProvider(provider, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("couldn't load image at \(url.path)")
    }
    return image
}

func savePNG(_ image: CGImage, to url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("couldn't create PNG writer for \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("couldn't write \(url.path)") }
}

/// Resamples `image` into exactly `width`x`height` pixels. Only ever called with a target at
/// or below the cropped source's own resolution for the app icon (see `main`), so this is
/// always a downscale there — the one place it's used for an upscale is the menu bar glyph,
/// whose source is thousands of pixels and whose target is a couple hundred, i.e. nowhere
/// close to needing one.
func resize(_ image: CGImage, to size: (Int, Int), colorSpace: CGColorSpace? = nil) -> CGImage {
    let cs = colorSpace ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size.0, height: size.1, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("couldn't create resize context") }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.0, height: size.1))
    guard let result = ctx.makeImage() else { fail("resize failed") }
    return result
}

/// Finds the pixel bounding box of the actual artwork within `image`, so cropping doesn't
/// depend on assumptions about where the artwork sits in the canvas. For an image with an
/// alpha channel, "artwork" means non-transparent pixels. For a flat/opaque image (no useful
/// alpha), it means pixels whose brightness differs from the background sampled at the
/// image's own corners — true for `MochiAppIcon.png`, a light character on a dark backdrop.
func artworkBoundingBox(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    // CGImage pixel layout varies by source; force a known layout (8-bit RGBA) via a redraw
    // so the sampling loop below can rely on a fixed 4-byte stride instead of guessing.
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("couldn't create sampling context") }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let pixels = ctx.data else { fail("no sampling buffer") }
    let bytes = pixels.bindMemory(to: UInt8.self, capacity: w * h * 4)

    func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let o = (y * w + x) * 4
        return (bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3])
    }

    let hasUsefulAlpha = (0..<min(h, 50)).contains { y in pixel(0, y).a < 250 } || pixel(0, 0).a < 250
    let bg = pixel(2, 2)

    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let p = pixel(x, y)
            let isForeground: Bool
            if hasUsefulAlpha {
                isForeground = p.a > 15
            } else {
                let luminance = (Int(p.r) + Int(p.g) + Int(p.b)) / 3
                let bgLuminance = (Int(bg.r) + Int(bg.g) + Int(bg.b)) / 3
                isForeground = abs(luminance - bgLuminance) > 40
            }
            if isForeground {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { fail("found no artwork (image looks blank)") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// A square crop centered on `bbox`, sized so the artwork fills roughly `fillRatio` of the
/// frame, clamped to the source image's own bounds — this is what guarantees we never
/// upscale: if the ideal padded frame would exceed the source, we use the largest square
/// that actually fits instead of reaching outside the image.
func squareCropFrame(for bbox: CGRect, in imageSize: (Int, Int), fillRatio: CGFloat) -> CGRect {
    let bboxMax = max(bbox.width, bbox.height)
    var side = bboxMax / fillRatio
    side = min(side, CGFloat(min(imageSize.0, imageSize.1)))
    let cx = bbox.midX, cy = bbox.midY
    var x = cx - side / 2
    var y = cy - side / 2
    x = max(0, min(x, CGFloat(imageSize.0) - side))
    y = max(0, min(y, CGFloat(imageSize.1) - side))
    return CGRect(x: x.rounded(), y: y.rounded(), width: side.rounded(), height: side.rounded())
}

/// A crop around `bbox` preserving its own aspect ratio (not forced square) — used for the
/// menu bar glyph, which is wider than it is tall and should stay that way.
func paddedCropFrame(for bbox: CGRect, in imageSize: (Int, Int), paddingRatio: CGFloat) -> CGRect {
    let padX = bbox.width * paddingRatio
    let padY = bbox.height * paddingRatio
    var rect = bbox.insetBy(dx: -padX, dy: -padY)
    rect.origin.x = max(0, rect.origin.x)
    rect.origin.y = max(0, rect.origin.y)
    rect.size.width = min(rect.width, CGFloat(imageSize.0) - rect.origin.x)
    rect.size.height = min(rect.height, CGFloat(imageSize.1) - rect.origin.y)
    return rect.integral
}

// MARK: - App icon

func generateAppIcon() {
    let sourceURL = designSourcesDir.appendingPathComponent("MochiAppIcon.png")
    guard fm.fileExists(atPath: sourceURL.path) else { fail("missing \(sourceURL.path)") }
    let source = loadCGImage(sourceURL)
    let bbox = artworkBoundingBox(source)
    // 0.37 keeps generous, deliberate padding around the character (consistent with the
    // source artwork's own dark full-bleed backdrop) while still reading clearly as an app
    // icon at Finder/Dock sizes.
    let frame = squareCropFrame(for: bbox, in: (source.width, source.height), fillRatio: 0.37)
    guard let master = source.cropping(to: frame) else { fail("app icon crop failed") }
    print("App icon: source \(source.width)x\(source.height), artwork bbox \(bbox), cropped master \(Int(frame.width))x\(Int(frame.height)) (no upscale: master ≥ every exported size)")

    let outputDir = rootDir.appendingPathComponent("Resources/AppIcon.iconset")
    try? fm.removeItem(at: outputDir)
    try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let sizes: [(name: String, points: Int, scale: Int)] = [
        ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
        ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
        ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
        ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
        ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2)
    ]
    for entry in sizes {
        let pixels = entry.points * entry.scale
        let resized = pixels == Int(frame.width) ? master : resize(master, to: (pixels, pixels))
        savePNG(resized, to: outputDir.appendingPathComponent("\(entry.name).png"))
    }
    print("Wrote \(sizes.count) iconset images to \(outputDir.path)")
}

// MARK: - Menu bar template

func generateMenuBarTemplate() {
    let sourceURL = designSourcesDir.appendingPathComponent("MochiMenuBarGlyph.png")
    guard fm.fileExists(atPath: sourceURL.path) else { fail("missing \(sourceURL.path)") }
    let source = loadCGImage(sourceURL)
    let bbox = artworkBoundingBox(source)
    // Tighter padding than the app icon: status-bar icons sit among tightly-drawn system
    // glyphs (Wi-Fi, Control Center, battery) and shouldn't look like they're floating in
    // extra whitespace relative to them.
    let frame = paddedCropFrame(for: bbox, in: (source.width, source.height), paddingRatio: 0.12)
    guard let cropped = source.cropping(to: frame) else { fail("menu bar crop failed") }

    // Render at a fixed, generous pixel height so the single exported PNG stays crisp however
    // large AppKit is asked to draw it — see MenuBarLabel.swift, which sets the NSImage's
    // *point* size explicitly rather than relying on filename-based @2x/@3x resolution (this
    // target has no asset catalog for that convention to apply to).
    let targetHeight = 216
    let targetWidth = Int((CGFloat(targetHeight) * frame.width / frame.height).rounded())
    let resized = resize(cropped, to: (targetWidth, targetHeight))

    // Template images are rendered by AppKit using ONLY the alpha channel — color is
    // ignored — but normalizing the RGB to pure black here keeps the asset self-describing
    // and avoids relying on that rule for an image that doesn't already happen to be black.
    let templatized = templatize(resized)

    let outputURL = rootDir.appendingPathComponent("Sources/MochiApp/Resources/MochiMenuBarTemplate.png")
    savePNG(templatized, to: outputURL)
    print("Menu bar template: source \(source.width)x\(source.height), artwork bbox \(bbox), exported \(targetWidth)x\(targetHeight) -> \(outputURL.path)")
}

/// Replaces every pixel's RGB with black, leaving alpha untouched — turns a colored/white
/// silhouette-on-transparency image into a proper black-on-transparency template source.
func templatize(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let cs = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = w * 4
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let buffer = ctx.data else { fail("couldn't create templatize context") }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = buffer.bindMemory(to: UInt8.self, capacity: w * h * 4)
    for i in stride(from: 0, to: w * h * 4, by: 4) {
        bytes[i] = 0
        bytes[i + 1] = 0
        bytes[i + 2] = 0
        // bytes[i+3] (alpha) is left as-is.
    }
    guard let result = ctx.makeImage() else { fail("templatize failed") }
    return result
}

// MARK: - Entry point

generateAppIcon()
generateMenuBarTemplate()
