// SPDX-License-Identifier: Apache-2.0
//
// Generates the ContainerMenuBar app icon: an isometric 3D box (white/grey faces
// with a soft drop shadow) on a near-black rounded-square plate — a simple,
// material-style mark.
//
// Usage:
//   swift Scripts/generate-icon.swift <output.icns> [preview.png]
//
// Requires macOS (AppKit + iconutil).

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <output.icns> [preview.png]\n".utf8))
    exit(2)
}
let outputICNS = arguments[1]
let previewPNG: String? = arguments.count >= 3 ? arguments[2] : nil

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func renderPNG(side: CGFloat) -> Data {
    let pixels = Int(side)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))

    // Rounded-square plate (Apple-style continuous-ish corner) with a soft shadow.
    let margin = side * 0.085
    let plate = CGRect(x: margin, y: margin, width: side - 2 * margin, height: side - 2 * margin)
    let cornerRadius = plate.width * 0.2237
    let platePath = NSBezierPath(roundedRect: plate, xRadius: cornerRadius, yRadius: cornerRadius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.03, color: color(0x000000, 0.55).cgColor)
    color(0x121212).setFill()
    platePath.fill()
    ctx.restoreGState()

    // Subtle radial sheen on the plate.
    ctx.saveGState()
    platePath.addClip()
    if let sheen = NSGradient(colors: [color(0x242424), color(0x0B0B0B)]) {
        sheen.draw(in: plate, relativeCenterPosition: NSPoint(x: -0.1, y: 0.28))
    }
    ctx.restoreGState()

    // Isometric cube geometry (y-up). Light reads from the upper-left.
    let cx = side / 2
    let cy = side / 2 - side * 0.01
    let a = plate.width * 0.255          // horizontal half-width
    let v = a * 0.5                      // rhombus vertical offset (2:1 iso)
    let s = a * 1.08                     // extruded side height

    let top = CGPoint(x: cx, y: cy + v + s / 2)
    let rightTop = CGPoint(x: cx + a, y: cy + s / 2)
    let leftTop = CGPoint(x: cx - a, y: cy + s / 2)
    let frontTop = CGPoint(x: cx, y: cy - v + s / 2)
    let frontBottom = CGPoint(x: cx, y: cy - v - s / 2)
    let leftBottom = CGPoint(x: cx - a, y: cy - s / 2)
    let rightBottom = CGPoint(x: cx + a, y: cy - s / 2)

    func face(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.close()
        return path
    }

    let topFace = face([top, rightTop, frontTop, leftTop])
    let leftFace = face([leftTop, frontTop, frontBottom, leftBottom])
    let rightFace = face([rightTop, frontTop, frontBottom, rightBottom])
    let silhouette = face([top, rightTop, rightBottom, frontBottom, leftBottom, leftTop])

    // One soft drop shadow cast by the whole cube.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: side * 0.012, height: -side * 0.02), blur: side * 0.035, color: color(0x000000, 0.5).cgColor)
    color(0x000000, 0.001).setFill()   // near-invisible fill that still casts the shadow
    silhouette.fill()
    ctx.restoreGState()

    // Faces (flat material shades).
    color(0xF5F5F5).setFill(); topFace.fill()     // top — near white
    color(0xAEAEAE).setFill(); leftFace.fill()    // left — grey 400/500
    color(0x6E6E6E).setFill(); rightFace.fill()   // right — grey 600/700

    // Subtle edge separation.
    color(0x000000, 0.12).setStroke()
    let edge = NSBezierPath()
    edge.lineWidth = max(1, side * 0.0035)
    edge.lineJoinStyle = .round
    for path in [topFace, leftFace, rightFace] { edge.append(path) }
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Build the iconset and run iconutil.
let fileManager = FileManager.default
let iconset = NSTemporaryDirectory() + "ContainerMenuBar-\(ProcessInfo.processInfo.processIdentifier).iconset"
try? fileManager.removeItem(atPath: iconset)
try fileManager.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(size: CGFloat, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

var cache: [CGFloat: Data] = [:]
for entry in entries {
    let data = cache[entry.size] ?? renderPNG(side: entry.size)
    cache[entry.size] = data
    try data.write(to: URL(fileURLWithPath: iconset + "/" + entry.name))
}

if let previewPNG {
    try (cache[1024] ?? renderPNG(side: 1024)).write(to: URL(fileURLWithPath: previewPNG))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", outputICNS]
try process.run()
process.waitUntilExit()
try? fileManager.removeItem(atPath: iconset)

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(outputICNS)")
