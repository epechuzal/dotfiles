import AppKit
import Foundation

// Renders an SF Symbol as a tinted PNG.
// Usage: sf-icon <symbol> <r> <g> <b> <alpha> <output_path> [size]
// Colors are 0.0-1.0 floats. Size defaults to 48px.
guard CommandLine.arguments.count >= 7 else {
    fputs("Usage: sf-icon <symbol> <r> <g> <b> <alpha> <output> [size]\n", stderr)
    exit(1)
}

let symbolName = CommandLine.arguments[1]
let r = CGFloat(Double(CommandLine.arguments[2])!)
let g = CGFloat(Double(CommandLine.arguments[3])!)
let b = CGFloat(Double(CommandLine.arguments[4])!)
let a = CGFloat(Double(CommandLine.arguments[5])!)
let outputPath = CommandLine.arguments[6]
let size = CGFloat(CommandLine.arguments.count > 7 ? Double(CommandLine.arguments[7])! : 48)

guard let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    fputs("Symbol not found: \(symbolName)\n", stderr)
    exit(1)
}

let color = NSColor(red: r, green: g, blue: b, alpha: a)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .medium)
    .applying(.init(paletteColors: [color]))
let configured = img.withSymbolConfiguration(config)!

let targetSize = NSSize(width: size, height: size)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(targetSize.width), pixelsHigh: Int(targetSize.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let imgSize = configured.size
let x = (targetSize.width - imgSize.width) / 2
let y = (targetSize.height - imgSize.height) / 2
configured.draw(in: NSRect(x: x, y: y, width: imgSize.width, height: imgSize.height))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to create PNG\n", stderr)
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outputPath))
