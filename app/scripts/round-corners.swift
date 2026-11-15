#!/usr/bin/env swift
// Обрезает снимок по форме окна: скруглённые углы и прозрачность за ними.
// Запуск: swift scripts/round-corners.swift <вход.png> <выход.png> <радиус в пикселях>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let radius = Double(arguments[3]),
      let source = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])),
      let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: round-corners <in.png> <out.png> <radius>\n".utf8))
    exit(1)
}

let width = cgImage.width, height = cgImage.height
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rect = CGRect(x: 0, y: 0, width: width, height: height)
context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
context.draw(cgImage, in: rect)

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
