#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let canvasSize = 1024

private enum IconError: Error, CustomStringConvertible {
    case invalidArguments
    case bitmapCreation
    case pngEncoding

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: generate-soulnest-master-icons.swift <release-output> <debug-output>"
        case .bitmapCreation:
            return "unable to create the icon bitmap"
        case .pngEncoding:
            return "unable to encode the icon as PNG"
        }
    }
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    guard let value = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations)
    else {
        preconditionFailure("invalid SoulNest gradient")
    }
    return value
}

private func heartPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 354))
    path.addCurve(
        to: CGPoint(x: 300, y: 686),
        control1: CGPoint(x: 478, y: 454),
        control2: CGPoint(x: 300, y: 548))
    path.addCurve(
        to: CGPoint(x: 512, y: 694),
        control1: CGPoint(x: 300, y: 792),
        control2: CGPoint(x: 446, y: 818))
    path.addCurve(
        to: CGPoint(x: 724, y: 686),
        control1: CGPoint(x: 578, y: 818),
        control2: CGPoint(x: 724, y: 792))
    path.addCurve(
        to: CGPoint(x: 512, y: 354),
        control1: CGPoint(x: 724, y: 548),
        control2: CGPoint(x: 546, y: 454))
    path.closeSubpath()
    return path
}

private func drawNestArc(
    in context: CGContext,
    start: CGPoint,
    end: CGPoint,
    control1: CGPoint,
    control2: CGPoint,
    stroke: CGColor,
    width: CGFloat)
{
    let path = CGMutablePath()
    path.move(to: start)
    path.addCurve(to: end, control1: control1, control2: control2)

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(width)
    context.setStrokeColor(stroke)
    context.setShadow(offset: .zero, blur: 20, color: color(0xF05BA3, alpha: 0.22))
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

private func drawSpark(in context: CGContext) {
    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(8)
    context.setStrokeColor(color(0xF7C7E0, alpha: 0.72))
    context.setShadow(offset: .zero, blur: 14, color: color(0xF7C7E0, alpha: 0.65))

    context.move(to: CGPoint(x: 704, y: 772))
    context.addLine(to: CGPoint(x: 704, y: 846))
    context.move(to: CGPoint(x: 667, y: 809))
    context.addLine(to: CGPoint(x: 741, y: 809))
    context.strokePath()
    context.restoreGState()
}

private func drawDebugBadge(in context: CGContext) {
    let center = CGPoint(x: 836, y: 166)
    let outer = CGMutablePath()
    outer.move(to: CGPoint(x: center.x, y: center.y + 70))
    outer.addLine(to: CGPoint(x: center.x + 70, y: center.y))
    outer.addLine(to: CGPoint(x: center.x, y: center.y - 70))
    outer.addLine(to: CGPoint(x: center.x - 70, y: center.y))
    outer.closeSubpath()

    context.saveGState()
    context.setShadow(offset: .zero, blur: 22, color: color(0x48D7F2, alpha: 0.6))
    context.setFillColor(color(0x48D7F2))
    context.addPath(outer)
    context.fillPath()
    context.restoreGState()

    let inner = CGMutablePath()
    inner.move(to: CGPoint(x: center.x, y: center.y + 37))
    inner.addLine(to: CGPoint(x: center.x + 37, y: center.y))
    inner.addLine(to: CGPoint(x: center.x, y: center.y - 37))
    inner.addLine(to: CGPoint(x: center.x - 37, y: center.y))
    inner.closeSubpath()
    context.setFillColor(color(0xD9E2EA))
    context.addPath(inner)
    context.fillPath()
}

private func renderIcon(debug: Bool, outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0)
    else {
        throw IconError.bitmapCreation
    }

    bitmap.size = NSSize(width: canvasSize, height: canvasSize)
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconError.bitmapCreation
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    context.setFillColor(color(0x10152C))
    context.fill(bounds)

    let background = gradient(
        [color(0x5A275F), color(0x2A1A43), color(0x10152C)],
        locations: [0, 0.56, 1])
    context.drawRadialGradient(
        background,
        startCenter: CGPoint(x: 414, y: 625),
        startRadius: 0,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 760,
        options: [.drawsAfterEndLocation])

    let orb = CGRect(x: 190, y: 176, width: 644, height: 644)
    context.setLineWidth(7)
    context.setStrokeColor(color(0xB985C7, alpha: 0.28))
    context.strokeEllipse(in: orb)

    let heart = heartPath()
    context.saveGState()
    context.setShadow(offset: .zero, blur: 44, color: color(0xF05BA3, alpha: 0.52))
    context.setFillColor(color(0xF05BA3))
    context.addPath(heart)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(heart)
    context.clip()
    let heartFill = gradient(
        [color(0xEC5CA4), color(0xFB8CB5), color(0xFFC4B5)],
        locations: [0, 0.5, 1])
    context.drawLinearGradient(
        heartFill,
        start: CGPoint(x: 512, y: 350),
        end: CGPoint(x: 512, y: 810),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    let highlight = CGMutablePath()
    highlight.move(to: CGPoint(x: 405, y: 704))
    highlight.addCurve(
        to: CGPoint(x: 475, y: 737),
        control1: CGPoint(x: 429, y: 743),
        control2: CGPoint(x: 459, y: 750))
    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(13)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.3))
    context.setShadow(offset: .zero, blur: 9, color: color(0xFFFFFF, alpha: 0.32))
    context.addPath(highlight)
    context.strokePath()
    context.restoreGState()

    drawNestArc(
        in: context,
        start: CGPoint(x: 246, y: 307),
        end: CGPoint(x: 778, y: 307),
        control1: CGPoint(x: 363, y: 188),
        control2: CGPoint(x: 661, y: 188),
        stroke: color(0xF9AE8F),
        width: 55)
    drawNestArc(
        in: context,
        start: CGPoint(x: 294, y: 247),
        end: CGPoint(x: 730, y: 247),
        control1: CGPoint(x: 388, y: 160),
        control2: CGPoint(x: 636, y: 160),
        stroke: color(0xEC5AA5),
        width: 47)
    drawNestArc(
        in: context,
        start: CGPoint(x: 356, y: 194),
        end: CGPoint(x: 668, y: 194),
        control1: CGPoint(x: 424, y: 132),
        control2: CGPoint(x: 600, y: 132),
        stroke: color(0xA66AE8),
        width: 39)

    context.setFillColor(color(0xF5AA8C))
    context.fillEllipse(in: CGRect(x: 245, y: 580, width: 38, height: 38))
    context.setFillColor(color(0xE45C9F))
    context.fillEllipse(in: CGRect(x: 748, y: 615, width: 34, height: 34))
    context.setFillColor(color(0xA66AE8, alpha: 0.88))
    context.fillEllipse(in: CGRect(x: 747, y: 229, width: 34, height: 34))

    drawSpark(in: context)
    if debug {
        drawDebugBadge(in: context)
    }

    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(
        using: .png,
        properties: [.compressionFactor: 1])
    else {
        throw IconError.pngEncoding
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try data.write(to: outputURL, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconError.invalidArguments
    }

    let releaseURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let debugURL = URL(fileURLWithPath: CommandLine.arguments[2])
    try renderIcon(debug: false, outputURL: releaseURL)
    try renderIcon(debug: true, outputURL: debugURL)
    print("Generated SoulNest 1024×1024 Release and Debug master icons.")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
