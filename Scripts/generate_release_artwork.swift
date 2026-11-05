import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_release_artwork.swift <app-icon.png> <dmg-background.png>\n", stderr)
    exit(64)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let backgroundURL = URL(fileURLWithPath: CommandLine.arguments[2])

try FileManager.default.createDirectory(at: iconURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: true)

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
}

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
    )
}

func makeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
    NSBezierPath(roundedRect: canvas.insetBy(dx: 42, dy: 42), xRadius: 225, yRadius: 225).fill()

    let body = NSRect(x: 188, y: 348, width: 572, height: 328)
    let terminal = NSRect(x: 760, y: 448, width: 74, height: 128)
    // Match BatteryLevelSymbol's menu-bar geometry: rounded body, terminal, and fill.
    let bodyPath = NSBezierPath(
        roundedRect: body,
        xRadius: body.height * 0.23,
        yRadius: body.height * 0.23
    )
    bodyPath.lineWidth = 32
    NSColor.white.withAlphaComponent(0.96).setStroke()
    bodyPath.stroke()
    NSColor.white.withAlphaComponent(0.93).setFill()
    NSBezierPath(
        roundedRect: terminal,
        xRadius: terminal.height * 0.24,
        yRadius: terminal.height * 0.24
    ).fill()

    // Fixed 75% level: visual identity, not a live battery reading.
    let charge = NSRect(x: 226, y: 386, width: 372, height: 252)
    NSColor.white.withAlphaComponent(0.93).setFill()
    NSBezierPath(
        roundedRect: charge,
        xRadius: charge.height * 0.20,
        yRadius: charge.height * 0.20
    ).fill()

    return image
}

func makeDMGBackground() -> NSImage {
    let size = NSSize(width: 1200, height: 760)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(origin: .zero, size: size)
    // Keep installer canvas deliberately quiet. Finder icons remain focal point.
    NSColor(calibratedRed: 0.963, green: 0.963, blue: 0.975, alpha: 1).setFill()
    canvas.fill()

    let start = NSPoint(x: 464, y: 380)
    let end = NSPoint(x: 770, y: 380)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.line(to: end)
    arrow.lineWidth = 3.5
    arrow.lineCapStyle = .round
    NSColor(calibratedWhite: 0.30, alpha: 0.72).setStroke()
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: end)
    arrowHead.line(to: NSPoint(x: 740, y: 402))
    arrowHead.move(to: end)
    arrowHead.line(to: NSPoint(x: 740, y: 358))
    arrowHead.lineWidth = 3.5
    arrowHead.lineCapStyle = .round
    arrowHead.stroke()

    drawText(
        "Drag BitFi to Applications",
        in: NSRect(x: 260, y: 180, width: 680, height: 38),
        font: .systemFont(ofSize: 20, weight: .medium),
        color: NSColor(calibratedWhite: 0.22, alpha: 0.72),
        alignment: .center
    )

    return image
}

try savePNG(makeIcon(), to: iconURL)
try savePNG(makeDMGBackground(), to: backgroundURL)
