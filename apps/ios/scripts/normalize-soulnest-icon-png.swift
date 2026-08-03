#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
            return "unable to create opaque RGB context for \(url.path)"
        case let .pngEncoding(url):
            return "unable to encode opaque RGB PNG for \(url.path)"
        }
    }
}

private func normalize(_ url: URL) throws {
    guard FileManager.default.isReadableFile(atPath: url.path),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NormalizeError.unreadable(url)
    }

    guard sourceImage.width > 0, sourceImage.height > 0 else {
        throw NormalizeError.invalidImage(url)
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))
    guard let context = CGContext(
        data: nil,
        width: sourceImage.width,
        height: sourceImage.height,
        bitsPerComponent: 8,
        bytesPerRow: sourceImage.width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue)
    else {
        throw NormalizeError.bitmapCreation(url)
    }

    let bounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    context.interpolationQuality = .high
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(bounds)
    context.draw(sourceImage, in: bounds)

    guard let normalizedImage = context.makeImage() else {
        throw NormalizeError.bitmapCreation(url)
    }

    let temporaryURL = url.deletingLastPathComponent()
        .appendingPathComponent(".soulnest-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    guard let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil)
    else {
        throw NormalizeError.pngEncoding(url)
    }

    CGImageDestinationAddImage(destination, normalizedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NormalizeError.pngEncoding(url)
    }

    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
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
