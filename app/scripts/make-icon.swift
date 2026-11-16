#!/usr/bin/env swift
// Рисует значок приложения (стеклянная плитка с прозрачным фоном и пиксельный Стив) и собирает Steve.icns.
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

    // значок как в макете: стеклянная плитка со скруглением и прозрачным фоном вокруг, внутри бирюзовое стекло и Стив.
    // Всё считается от размера в долях, чтобы маленькие размеры выглядели так же, как большой.
    let outer = NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86)
    let outerPath = NSBezierPath(roundedRect: outer, xRadius: s * 0.2, yRadius: s * 0.2)

    // внешняя стеклянная рамка: еле заметная заливка и светлый ободок
    NSColor.white.withAlphaComponent(0.07).setFill()
    outerPath.fill()
    NSGraphicsContext.saveGraphicsState()
    outerPath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: outer, angle: -90) // блик сверху
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.55).setStroke()
    outerPath.lineWidth = max(1, s * 0.012)
    outerPath.stroke()

    // внутренняя плитка из бирюзового стекла
    let inner = outer.insetBy(dx: s * 0.06, dy: s * 0.06)
    let innerPath = NSBezierPath(roundedRect: inner, xRadius: s * 0.15, yRadius: s * 0.15)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 0.50, alpha: 0.96), NSColor(red: 0.13, green: 0.33, blue: 0.39, alpha: 0.98)])!
        .draw(in: innerPath, angle: -80)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    innerPath.lineWidth = max(1, s * 0.006)
    innerPath.stroke()

    // Стив: те же прямоугольники, что в SVG (область 128 на 128), сверху вниз
    let unit = s * 0.46 / 128
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
