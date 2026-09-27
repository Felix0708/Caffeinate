import AppKit

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext

// 1. App Icon Squircle Path (Apple standard macOS app squircle)
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: squircleRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.addPath(path)
context.clip()

// 2. Rich Dark Coffee Background Gradient
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    NSColor(red: 0.28, green: 0.17, blue: 0.11, alpha: 1.0).cgColor, // Warm espresso top
    NSColor(red: 0.13, green: 0.08, blue: 0.05, alpha: 1.0).cgColor  // Deep roast bottom
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// 3. Subtle Inner Glow / Border
context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
context.setLineWidth(6.0)
context.addPath(path)
context.strokePath()

// 4. White / Warm-cream Coffee Cup Symbol (SF Symbols: cup.and.saucer.fill)
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(.init(paletteColors: [
        NSColor(red: 0.98, green: 0.94, blue: 0.90, alpha: 1.0) // Creamy white
    ]))

if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let symbolRect = CGRect(x: 190, y: 220, width: 644, height: 500)
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiffData),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Failed to get PNG data")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Successfully generated \(outputPath)")
