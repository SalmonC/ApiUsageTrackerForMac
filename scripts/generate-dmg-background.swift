import AppKit
import Foundation

let width = 820
let height = 460
let scriptURL = URL(fileURLWithPath: #filePath)
let scriptDir = scriptURL.deletingLastPathComponent()
let out = scriptDir.appendingPathComponent("assets/dmg-background.png")

let title = "Install QuotaPulse"
let subtitle = "Drag QuotaPulse.app to Applications"
let cn = "将 QuotaPulse.app 拖到 Applications 完成安装"
let hintEN = "First launch blocked? System Settings > Privacy & Security > Open Anyway"
let hintCN = "首次启动被拦截？前往 系统设置 > 隐私与安全性 > 仍要打开"

let titleFont = NSFont.systemFont(ofSize: 33, weight: .semibold)
let subtitleFont = NSFont.systemFont(ofSize: 18, weight: .medium)
let cnFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)
let hintFont = NSFont.systemFont(ofSize: 12, weight: .regular)

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)
]
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: subtitleFont,
    .foregroundColor: NSColor(calibratedRed: 0.27, green: 0.33, blue: 0.44, alpha: 0.95)
]
let cnAttrs: [NSAttributedString.Key: Any] = [
    .font: cnFont,
    .foregroundColor: NSColor(calibratedRed: 0.40, green: 0.45, blue: 0.55, alpha: 0.92)
]
let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: hintFont,
    .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.39, blue: 0.58, alpha: 0.88)
]
let titleSize = (title as NSString).size(withAttributes: titleAttrs)
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
let cnSize = (cn as NSString).size(withAttributes: cnAttrs)
let hintENSize = (hintEN as NSString).size(withAttributes: hintAttrs)
let hintCNSize = (hintCN as NSString).size(withAttributes: hintAttrs)

let rowSpacing: CGFloat = 6
let hintSpacing: CGFloat = 4
let horizontalPadding: CGFloat = 40
let verticalPadding: CGFloat = 18

let textBlockWidth = max(titleSize.width, subtitleSize.width, cnSize.width, hintENSize.width, hintCNSize.width)
let textBlockHeight = titleSize.height + subtitleSize.height + cnSize.height + hintENSize.height + hintCNSize.height + rowSpacing * 2 + hintSpacing * 2

let panelWidth = ceil(textBlockWidth + horizontalPadding * 2)
let panelHeight = ceil(textBlockHeight + verticalPadding * 2)
let panelX = (CGFloat(width) - panelWidth) / 2
let panelY: CGFloat = 292

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4,
    bitsPerPixel: 32
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let bg = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.968, green: 0.982, blue: 1.000, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.902, green: 0.934, blue: 0.988, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

func fillRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = lineWidth
    path.stroke()
}

func drawCentered(_ text: String, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
    let size = (text as NSString).size(withAttributes: attrs)
    (text as NSString).draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: y), withAttributes: attrs)
}

func drawSoftShadowedPath(_ path: NSBezierPath, shadowColor: NSColor, blur: CGFloat, offset: NSSize, fill: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    fill.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

let panelRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 20, yRadius: 20)
drawSoftShadowedPath(
    panelPath,
    shadowColor: NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.72, alpha: 0.12),
    blur: 18,
    offset: NSSize(width: 0, height: -8),
    fill: NSColor.white.withAlphaComponent(0.52)
)
strokeRoundedRect(panelRect, radius: 20, color: NSColor.white.withAlphaComponent(0.62))

let textStartY = panelY + panelHeight - verticalPadding - titleSize.height
let titleX = (CGFloat(width) - titleSize.width) / 2
let subtitleX = (CGFloat(width) - subtitleSize.width) / 2
let cnX = (CGFloat(width) - cnSize.width) / 2

(title as NSString).draw(
    at: NSPoint(x: titleX, y: textStartY),
    withAttributes: titleAttrs
)

let subtitleY = textStartY - rowSpacing - subtitleSize.height
(subtitle as NSString).draw(
    at: NSPoint(x: subtitleX, y: subtitleY),
    withAttributes: subtitleAttrs
)

let cnY = subtitleY - rowSpacing - cnSize.height
(cn as NSString).draw(
    at: NSPoint(x: cnX, y: cnY),
    withAttributes: cnAttrs
)

let hintENY = cnY - hintSpacing - hintENSize.height
let hintENX = (CGFloat(width) - hintENSize.width) / 2
(hintEN as NSString).draw(
    at: NSPoint(x: hintENX, y: hintENY),
    withAttributes: hintAttrs
)

let hintCNY = hintENY - hintSpacing - hintCNSize.height
let hintCNX = (CGFloat(width) - hintCNSize.width) / 2
(hintCN as NSString).draw(
    at: NSPoint(x: hintCNX, y: hintCNY),
    withAttributes: hintAttrs
)

// Icon anchors (for Finder icon centers)
let leftIconCenterX: CGFloat = 210
let rightIconCenterX: CGFloat = 595
let iconAnchorY: CGFloat = 146
let iconAnchorSize: CGFloat = 124
let iconRadius = iconAnchorSize / 2
let centerY = iconAnchorY + iconRadius

let leftHaloRect = NSRect(
    x: leftIconCenterX - iconRadius,
    y: iconAnchorY,
    width: iconAnchorSize,
    height: iconAnchorSize
)
let rightHaloRect = NSRect(
    x: rightIconCenterX - iconRadius,
    y: iconAnchorY,
    width: iconAnchorSize,
    height: iconAnchorSize
)
for rect in [leftHaloRect, rightHaloRect] {
    let haloPath = NSBezierPath(ovalIn: rect)
    drawSoftShadowedPath(
        haloPath,
        shadowColor: NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.78, alpha: 0.12),
        blur: 16,
        offset: NSSize(width: 0, height: -5),
        fill: NSColor.white.withAlphaComponent(0.36)
    )
    NSColor.white.withAlphaComponent(0.54).setStroke()
    haloPath.lineWidth = 1
    haloPath.stroke()
}

let logoX: CGFloat = 63
let logoY: CGFloat = 342
let logoBarColor = NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.96, alpha: 0.95)
for (index, height) in [18.0, 26.0, 34.0].enumerated() {
    let bar = NSRect(
        x: logoX + CGFloat(index) * 11,
        y: logoY,
        width: 8,
        height: CGFloat(height)
    )
    fillRoundedRect(bar, radius: 3, color: logoBarColor)
}

let brandAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.24, green: 0.33, blue: 0.48, alpha: 0.72)
]
("QuotaPulse" as NSString).draw(
    at: NSPoint(x: 108, y: 349),
    withAttributes: brandAttrs
)

// Draw a single-piece Apple-style arrow, optically centered between the two icon anchors.
let leftIconEdge = leftIconCenterX + iconRadius
let rightIconEdge = rightIconCenterX - iconRadius
let edgeClearance: CGFloat = 42
let startX = leftIconEdge + edgeClearance
let tipX = rightIconEdge - edgeClearance
let headLength: CGFloat = 42
let neckX = tipX - headLength
let shaftHalfHeight: CGFloat = 5.5
let headHalfHeight: CGFloat = 24

let arrowShaftPath = NSBezierPath(
    roundedRect: NSRect(
        x: startX,
        y: centerY - shaftHalfHeight,
        width: max(1, neckX - startX + 1),
        height: shaftHalfHeight * 2
    ),
    xRadius: shaftHalfHeight,
    yRadius: shaftHalfHeight
)

let arrowHeadPath = NSBezierPath()
arrowHeadPath.move(to: NSPoint(x: neckX, y: centerY - headHalfHeight))
arrowHeadPath.line(to: NSPoint(x: tipX, y: centerY))
arrowHeadPath.line(to: NSPoint(x: neckX, y: centerY + headHalfHeight))
arrowHeadPath.close()

let arrowCombinedPath = NSBezierPath()
arrowCombinedPath.append(arrowShaftPath)
arrowCombinedPath.append(arrowHeadPath)

let arrowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.20, green: 0.62, blue: 1.00, alpha: 0.96).cgColor,
        NSColor(calibratedRed: 0.09, green: 0.48, blue: 0.96, alpha: 0.98).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!

NSGraphicsContext.saveGraphicsState()
arrowCombinedPath.addClip()
cg.drawLinearGradient(
    arrowGradient,
    start: CGPoint(x: startX, y: centerY),
    end: CGPoint(x: tipX, y: centerY),
    options: []
)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.12).setStroke()
arrowShaftPath.lineWidth = 1
arrowShaftPath.stroke()
arrowHeadPath.lineWidth = 1
arrowHeadPath.stroke()

let footer = "Tip: Replace any older version when macOS asks."
let footerCN = "提示：如系统询问是否替换旧版本，请选择替换。"
let footerAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.37, green: 0.43, blue: 0.54, alpha: 0.70)
]
let footerY: CGFloat = 28
let footerCNSize = (footerCN as NSString).size(withAttributes: footerAttrs)
let footerSize = (footer as NSString).size(withAttributes: footerAttrs)
(footer as NSString).draw(
    at: NSPoint(x: (CGFloat(width) - footerSize.width) / 2, y: footerY + 18),
    withAttributes: footerAttrs
)
(footerCN as NSString).draw(
    at: NSPoint(x: (CGFloat(width) - footerCNSize.width) / 2, y: footerY),
    withAttributes: footerAttrs
)

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [.compressionFactor: 0.84])!
try data.write(to: out, options: .atomic)
print("generated \(out.path) \(data.count) bytes; panel \(Int(panelWidth))x\(Int(panelHeight))")
