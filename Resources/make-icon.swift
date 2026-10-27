// Dessine l'icône d'OutilScan et produit Resources/AppIcon.icns.
// Usage : swift Resources/make-icon.swift
import AppKit

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

func drawIcon(in ctx: CGContext) {
    // Grille des icônes macOS : contenu de 824 px centré, coins arrondis.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Ombre portée de la tuile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1B4FBF)); ctx.fillPath()
    ctx.restoreGState()

    // Fond : dégradé bleu.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    linearGradient(ctx, [color(0x3C8DF5), color(0x1747B8)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // Feuille de papier qui sort du scanner.
    let sheet = CGRect(x: 292, y: 360, width: 440, height: 470)
    let fold: CGFloat = 92
    let sheetPath = CGMutablePath()
    sheetPath.move(to: CGPoint(x: sheet.minX, y: sheet.minY))
    sheetPath.addLine(to: CGPoint(x: sheet.minX, y: sheet.maxY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY))
    sheetPath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x0A1F55, 0.45))
    ctx.addPath(sheetPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()

    // Coin replié.
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
    corner.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY - fold + 10))
    corner.addQuadCurve(to: CGPoint(x: sheet.maxX - fold + 10, y: sheet.maxY - fold),
                        control: CGPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
    corner.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
    corner.closeSubpath()
    ctx.addPath(corner); ctx.setFillColor(color(0xD3DEF0)); ctx.fillPath()

    // Lignes de texte du document.
    let lineColor = color(0x9AAAC4)
    var y = sheet.maxY - 70
    let widths: [CGFloat] = [190, 300, 340, 260, 340, 300, 220]
    for (i, width) in widths.enumerated() {
        let height: CGFloat = i == 0 ? 26 : 18
        let rect = CGRect(x: sheet.minX + 48, y: y, width: width, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        ctx.setFillColor(i == 0 ? color(0x31456B) : lineColor); ctx.fillPath()
        y -= i == 0 ? 56 : 44
    }

    // Faisceau de numérisation : halo puis ligne lumineuse.
    let beamY: CGFloat = 520
    ctx.saveGState()
    ctx.clip(to: CGRect(x: sheet.minX - 40, y: beamY - 70, width: sheet.width + 80, height: 140))
    linearGradient(ctx, [color(0x38E1C6, 0), color(0x38E1C6, 0.45), color(0x38E1C6, 0)],
                   from: CGPoint(x: 512, y: beamY - 70), to: CGPoint(x: 512, y: beamY + 70))
    ctx.restoreGState()
    let beam = CGRect(x: sheet.minX - 34, y: beamY - 7, width: sheet.width + 68, height: 14)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: color(0x5FFFE3, 0.9))
    ctx.addPath(CGPath(roundedRect: beam, cornerWidth: 7, cornerHeight: 7, transform: nil))
    ctx.setFillColor(color(0xB9FFF3)); ctx.fillPath()
    ctx.restoreGState()

    // Corps du scanner, devant la feuille.
    let body = CGRect(x: 196, y: 196, width: 632, height: 210)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 64, cornerHeight: 64, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x07173F, 0.5))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x23314D)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    linearGradient(ctx, [color(0x3F516F), color(0x1C2840)], from: CGPoint(x: 512, y: body.maxY), to: CGPoint(x: 512, y: body.minY))
    ctx.restoreGState()

    // Fente de sortie du papier et voyant.
    let slot = CGRect(x: sheet.minX - 22, y: body.maxY - 46, width: sheet.width + 44, height: 16)
    ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.setFillColor(color(0x0B111E)); ctx.fillPath()
    let led = CGRect(x: body.maxX - 112, y: body.minY + 58, width: 40, height: 40)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: color(0x5FFFE3, 0.9))
    ctx.addEllipse(in: led); ctx.setFillColor(color(0x5FFFE3)); ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(_ pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let resources = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "✔ Resources/AppIcon.icns créé" : "✘ iconutil a échoué")
