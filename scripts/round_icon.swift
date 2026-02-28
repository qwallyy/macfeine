#!/usr/bin/env swift
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

let rawArgs = CommandLine.arguments
var args: [String]
if let separatorIndex = rawArgs.firstIndex(of: "--") {
    args = Array(rawArgs[(separatorIndex + 1)...])
} else {
    args = Array(rawArgs.dropFirst())
}

if args.first == "--" {
    args.removeFirst()
}

guard args.count >= 2 else {
    fail("Usage: round_icon.swift <input.png> <output.png> [radius_fraction]")
}

let inputURL = URL(fileURLWithPath: args[0])
let outputURL = URL(fileURLWithPath: args[1])
let radiusFraction = (args.count >= 3 ? Double(args[2]) : nil) ?? 0.20

guard radiusFraction > 0.0, radiusFraction < 0.5 else {
    fail("radius_fraction must be between 0 and 0.5")
}

guard
    let sourceData = try? Data(contentsOf: inputURL),
    let sourceRep = NSBitmapImageRep(data: sourceData)
else {
    fail("Cannot read input image: \(inputURL.path)")
}

let width = sourceRep.pixelsWide
let height = sourceRep.pixelsHigh
guard width > 0, height > 0 else {
    fail("Input image has invalid dimensions")
}

let sourceImage = NSImage(size: NSSize(width: width, height: height))
sourceImage.addRepresentation(sourceRep)

guard let outputRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fail("Failed to allocate output bitmap")
}

let rect = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
guard let context = NSGraphicsContext(bitmapImageRep: outputRep) else {
    fail("Failed to create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

context.cgContext.setFillColor(NSColor.clear.cgColor)
context.cgContext.fill(rect)

let radius = CGFloat(radiusFraction) * min(rect.width, rect.height)
let clipPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clipPath.addClip()

sourceImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = outputRep.representation(using: .png, properties: [:]) else {
    fail("Failed to encode output PNG")
}

do {
    try pngData.write(to: outputURL)
} catch {
    fail("Failed writing output image: \(error.localizedDescription)")
}
