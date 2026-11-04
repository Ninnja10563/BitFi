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
    NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: canvas.insetBy(dx: 42, dy: 42), xRadius: 225, yRadius: 225).fill()

    let body = NSRect(x: 188, y: 348, width: 572, height: 328)
    let terminal = NSRect(x: 760, y: 448, width: 74, height: 128)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 54, yRadius: 54)
    bodyPath.lineWidth = 32
    NSColor.white.withAlphaComponent(0.96).setStroke()
    bodyPath.stroke()
    NSColor.white.withAlphaComponent(0.93).setFill()
    NSBezierPath(roundedRect: terminal, xRadius: 18, yRadius: 18).fill()

    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 530, y: 642))
    bolt.line(to: NSPoint(x: 411, y: 498))
    bolt.line(to: NSPoint(x: 490, y: 498))
    bolt.line(to: NSPoint(x: 457, y: 376))
    bolt.line(to: NSPoint(x: 604, y: 542))
    bolt.line(to: NSPoint(x: 520, y: 542))
    bolt.close()
    NSColor.white.setFill()
    bolt.fill()

    return image
}

func makeDMGBackground() -> NSImage {
    let size = NSSize(width: 1200, height: 760)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(origin: .zero, size: size)
    NSColor(calibratedRed: 0.075, green: 0.078, blue: 0.092, alpha: 1).setFill()
    canvas.fill()

    let panel = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 1112, height: 672), xRadius: 34, yRadius: 34)
    NSColor.white.withAlphaComponent(0.035).setFill()
    panel.fill()
    NSColor.white.withAlphaComponent(0.08).setStroke()
    panel.lineWidth = 1
    panel.stroke()

    let ghostBody = NSBezierPath(roundedRect: NSRect(x: 842, y: 510, width: 190, height: 112), xRadius: 18, yRadius: 18)
    ghostBody.lineWidth = 8
    NSColor(calibratedRed: 0.25, green: 0.55, blue: 1, alpha: 0.12).setStroke()
    ghostBody.stroke()
    NSColor(calibratedRed: 0.25, green: 0.55, blue: 1, alpha: 0.12).setFill()
    NSBezierPath(roundedRect: NSRect(x: 1034, y: 545, width: 18, height: 42), xRadius: 5, yRadius: 5).fill()

    drawText("BitFi", in: NSRect(x: 84, y: 630, width: 400, height: 68), font: .systemFont(ofSize: 56, weight: .bold), color: .white)
    drawText("Battery care. Clear status.", in: NSRect(x: 88, y: 587, width: 430, height: 36), font: .systemFont(ofSize: 23, weight: .regular), color: NSColor.white.withAlphaComponent(0.62))

    let start = NSPoint(x: 332, y: 336)
    let end = NSPoint(x: 864, y: 336)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.line(to: end)
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    NSColor(calibratedRed: 0.30, green: 0.60, blue: 1, alpha: 0.58).setStroke()
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: 864, y: 336))
    arrowHead.line(to: NSPoint(x: 832, y: 357))
    arrowHead.move(to: NSPoint(x: 864, y: 336))
    arrowHead.line(to: NSPoint(x: 832, y: 315))
    arrowHead.lineWidth = 3
    arrowHead.lineCapStyle = .round
    arrowHead.stroke()

    drawText("Drag BitFi to Applications", in: NSRect(x: 300, y: 188, width: 600, height: 42), font: .systemFont(ofSize: 22, weight: .medium), color: NSColor.white.withAlphaComponent(0.78), alignment: .center)
    drawText("Native macOS battery monitoring", in: NSRect(x: 300, y: 88, width: 600, height: 30), font: .systemFont(ofSize: 16, weight: .regular), color: NSColor.white.withAlphaComponent(0.35), alignment: .center)

    return image
}

try savePNG(makeIcon(), to: iconURL)
try savePNG(makeDMGBackground(), to: backgroundURL)
