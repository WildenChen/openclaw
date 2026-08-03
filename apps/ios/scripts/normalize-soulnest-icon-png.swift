#!/usr/bin/env swift

import AppKit
import Foundation

private enum NormalizeError: Error, CustomStringConvertible {
    case invalidArguments
    case unreadable(URL)
    case invalidImage(URL)
    case bitmapCreation(URL)
    case pngEncoding(URL)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: normalize-soulnest-icon-png.swift <png> [<png> ...]"
        case let .unreadable(url):
            return "unable to read \(url.path)"
        case let .invalidImage(url):
            return "invalid PNG image: \(url.path)"
        case let .bitmapCreation(url):
            return "unable to create RGB bitmap for \(url.path)"
        case let .pngEncoding(url):
            return "unable to encode RGB PNG for \(url.path)"
        }
    }
}

private func normalize(_ url: URL) throws {
    guard let data = try? Data(contentsOf: url) else {
        throw NormalizeError.unreadable(url)
    }
    guard let source = NSBitmapImageRep(data: data),
          let sourceImage = source.cgImage
    else {
        throw NormalizeError.invalidImage(url)
    }

    guard let destination = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: source.pixelsWide,
        pixelsHigh: source.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 24),
        let graphics = NSGraphicsContext(bitmapImageRep: destination)
    else {
        throw NormalizeError.bitmapCreation(url)
    }

    destination.size = NSSize(width: source.pixelsWide, height: source.pixelsHigh)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.setFillColor(NSColor.black.cgColor)
    let bounds = CGRect(x: 0, y: 0, width: source.pixelsWide, height: source.pixelsHigh)
    context.fill(bounds)
    context.draw(sourceImage, in: bounds)
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let normalized = destination.representation(
        using: .png,
        properties: [.compressionFactor: 1])
    else {
        throw NormalizeError.pngEncoding(url)
    }
    try normalized.write(to: url, options: .atomic)
}

do {
    guard CommandLine.arguments.count > 1 else {
        throw NormalizeError.invalidArguments
    }
    for path in CommandLine.arguments.dropFirst() {
        try normalize(URL(fileURLWithPath: path))
    }
    print("Normalized SoulNest App Store icons to opaque RGB PNGs.")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
