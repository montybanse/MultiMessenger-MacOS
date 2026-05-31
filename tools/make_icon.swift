import AppKit

// Erzeugt das App-Icon (1024x1024 PNG) – zwei überlappende Sprechblasen auf
// einem Farbverlauf im macOS-Squircle-Stil. Aufruf: swift make_icon.swift <out.png>

let size: CGFloat = 1024
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("Usage: make_icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

// Hintergrund-Squircle mit Rand (macOS-Icons haben einen transparenten Saum).
let margin = size * 0.085
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let corner = rect.width * 0.2237
let bg = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

cg.saveGState()
cg.addPath(bg)
cg.clip()
let colors = [
    NSColor(calibratedRed: 0.16, green: 0.49, blue: 1.00, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.45, green: 0.27, blue: 0.96, alpha: 1).cgColor
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
cg.drawLinearGradient(grad,
                      start: CGPoint(x: rect.minX, y: rect.maxY),
                      end: CGPoint(x: rect.maxX, y: rect.minY),
                      options: [])
cg.restoreGState()

// Sprechblase mit kleinem Schwanz nach unten.
func bubble(_ r: CGRect, fill: NSColor) {
    let cr = r.height * 0.30
    let body = CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil)
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: r.minX + r.width * 0.20, y: r.minY + r.height * 0.05))
    tail.addLine(to: CGPoint(x: r.minX + r.width * 0.06, y: r.minY - r.height * 0.20))
    tail.addLine(to: CGPoint(x: r.minX + r.width * 0.46, y: r.minY + r.height * 0.05))
    tail.closeSubpath()
    cg.setFillColor(fill.cgColor)
    cg.addPath(body); cg.fillPath()
    cg.setFillColor(fill.cgColor)
    cg.addPath(tail); cg.fillPath()
}

// Hintere Blase (transluzent) + vordere Blase (fast deckend weiß).
bubble(CGRect(x: size * 0.41, y: size * 0.45, width: size * 0.30, height: size * 0.235),
       fill: NSColor(white: 1, alpha: 0.55))
bubble(CGRect(x: size * 0.30, y: size * 0.33, width: size * 0.33, height: size * 0.26),
       fill: NSColor(white: 1, alpha: 0.97))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG-Erzeugung fehlgeschlagen\n".data(using: .utf8)!)
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("Icon geschrieben: \(outPath)")
