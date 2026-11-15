#!/usr/bin/env swift
// Рисует значок приложения (пиксельный Стив на тёмном скруглённом квадрате) и собирает Steve.icns.
// Запуск: swift scripts/make-icon.swift <папка для результата>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build")
let iconset = output.appendingPathComponent("Steve.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // фон: скруглённый квадрат с мягким градиентом
    let background = NSBezierPath(roundedRect: NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92), xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.36, alpha: 1), NSColor(red: 0.36, green: 0.22, blue: 0.62, alpha: 1)])!
        .draw(in: background, angle: -60)

    // Стив: те же прямоугольники, что в SVG (область 128 на 128), сверху вниз
    let unit = s * 0.92 * 0.74 / 128
    let originX = (s - 128 * unit) / 2
    let originY = (s - 128 * unit) / 2
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: originX + x * unit, y: originY + (128 - y - h) * unit, width: w * unit, height: h * unit)
    }
    NSColor(red: 176 / 255, green: 124 / 255, blue: 217 / 255, alpha: 1).setFill()
    [rect(32, 20, 64, 8), rect(24, 28, 80, 44), rect(28, 72, 12, 24), rect(48, 72, 12, 32), rect(68, 72, 12, 26), rect(88, 72, 12, 28)]
        .forEach { $0.fill() }
    NSColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1).setFill()
    [rect(46, 50, 8, 12), rect(74, 50, 8, 12)].forEach { $0.fill() }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("Steve.icns").path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
