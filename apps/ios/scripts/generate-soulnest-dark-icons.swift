#!/usr/bin/env swift

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum DarkIconError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidSource(URL)
    case filterFailure(URL)
    case renderFailure(URL)
    case encodeFailure(URL)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: generate-soulnest-dark-icons.swift <release-source> <release-output> <debug-source> <debug-output>"
        case let .invalidSource(url):
            return "unable to read source icon: \(url.path)"
        case let .filterFailure(url):
            return "unable to create dark appearance for: \(url.path)"
        case let .renderFailure(url):
            return "unable to render dark appearance for: \(url.path)"
        case let .encodeFailure(url):
            return "unable to encode dark appearance for: \(url.path)"
        }
    }
}

private let context = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
])

private func renderDark(sourceURL: URL, outputURL: URL) throws {
    guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
        throw DarkIconError.invalidSource(sourceURL)
    }

    guard let controls = CIFilter(name: "CIColorControls") else {
        throw DarkIconError.filterFailure(sourceURL)
    }
    controls.setValue(source, forKey: kCIInputImageKey)
    controls.setValue(-0.10, forKey: kCIInputBrightnessKey)
    controls.setValue(1.08, forKey: kCIInputContrastKey)
    controls.setValue(1.08, forKey: kCIInputSaturationKey)

    guard let controlled = controls.outputImage,
          let vignette = CIFilter(name: "CIVignette")
    else {
        throw DarkIconError.filterFailure(sourceURL)
    }
    vignette.setValue(controlled, forKey: kCIInputImageKey)
    vignette.setValue(0.34, forKey: kCIInputIntensityKey)
    vignette.setValue(1.35, forKey: kCIInputRadiusKey)

    guard let output = vignette.outputImage,
          let image = context.createCGImage(output, from: source.extent)
    else {
        throw DarkIconError.renderFailure(sourceURL)
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil)
    else {
        throw DarkIconError.encodeFailure(outputURL)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw DarkIconError.encodeFailure(outputURL)
    }
}

do {
    guard CommandLine.arguments.count == 5 else {
        throw DarkIconError.invalidArguments
    }

    try renderDark(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    try renderDark(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[3]),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[4]))
    print("Generated SoulNest Release and Debug dark appearance icons.")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
