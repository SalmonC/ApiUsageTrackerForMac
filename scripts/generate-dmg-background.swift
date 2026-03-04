import AppKit
import Foundation

let width = 820
let height = 460
let out = URL(fileURLWithPath: "/Users/salmonc/Code/Projects/MacTools/MacUsageTracker/scripts/assets/dmg-background.png")

let title = "Install QuotaPulse"
let subtitle = "Drag QuotaPulse.app to Applications"
let cn = "将 QuotaPulse.app 拖到 Applications 完成安装"
let hintEN = "First launch blocked? Open System Settings > Privacy & Security > Open Anyway"
let hintCN = "首次启动被拦截？前往 系统设置 > 隐私与安全性 > 仍要打开"

let titleFont = NSFont.systemFont(ofSize: 34, weight: .semibold)
let subtitleFont = NSFont.systemFont(ofSize: 20, weight: .medium)
let cnFont = NSFont.systemFont(ofSize: 14, weight: .regular)
let hintFont = NSFont.systemFont(ofSize: 12, weight: .regular)

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(calibratedWhite: 0.17, alpha: 1)
]
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: subtitleFont,
    .foregroundColor: NSColor(calibratedWhite: 0.32, alpha: 0.95)
]
let cnAttrs: [NSAttributedString.Key: Any] = [
    .font: cnFont,
    .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 0.92)
]
let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: hintFont,
    .foregroundColor: NSColor(calibratedRed: 0.29, green: 0.37, blue: 0.55, alpha: 0.9)
]

let titleSize = (title as NSString).size(withAttributes: titleAttrs)
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
let cnSize = (cn as NSString).size(withAttributes: cnAttrs)
let hintENSize = (hintEN as NSString).size(withAttributes: hintAttrs)
let hintCNSize = (hintCN as NSString).size(withAttributes: hintAttrs)

let rowSpacing: CGFloat = 7
let hintSpacing: CGFloat = 4
let horizontalPadding: CGFloat = 34
let verticalPadding: CGFloat = 16

let textBlockWidth = max(titleSize.width, subtitleSize.width, cnSize.width, hintENSize.width, hintCNSize.width)
let textBlockHeight = titleSize.height + subtitleSize.height + cnSize.height + hintENSize.height + hintCNSize.height + rowSpacing * 2 + hintSpacing * 2

let panelWidth = ceil(textBlockWidth + horizontalPadding * 2)
let panelHeight = ceil(textBlockHeight + verticalPadding * 2)
let panelX = (CGFloat(width) - panelWidth) / 2
let panelY: CGFloat = 286

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
        NSColor(calibratedRed: 0.955, green: 0.972, blue: 0.998, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.902, green: 0.934, blue: 0.985, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

let panelRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 20, yRadius: 20)
NSColor.white.withAlphaComponent(0.34).setFill()
panelPath.fill()

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
let iconAnchorY: CGFloat = 167
let iconAnchorSize: CGFloat = 110
let iconRadius = iconAnchorSize / 2
let centerY = iconAnchorY + iconRadius

NSColor.white.withAlphaComponent(0.32).setFill()
NSBezierPath(
    ovalIn: NSRect(
        x: leftIconCenterX - iconRadius,
        y: iconAnchorY,
        width: iconAnchorSize,
        height: iconAnchorSize
    )
).fill()
NSBezierPath(
    ovalIn: NSRect(
        x: rightIconCenterX - iconRadius,
        y: iconAnchorY,
        width: iconAnchorSize,
        height: iconAnchorSize
    )
).fill()

// Draw a single-piece Apple-style arrow, optically centered between the two icon anchors.
let leftIconEdge = leftIconCenterX + iconRadius
let rightIconEdge = rightIconCenterX - iconRadius
let edgeClearance: CGFloat = 48
let startX = leftIconEdge + edgeClearance
let tipX = rightIconEdge - edgeClearance
let headLength: CGFloat = 46
let neckX = tipX - headLength
let shaftHalfHeight: CGFloat = 6.5
let headHalfHeight: CGFloat = 28

let arrowPath = NSBezierPath()
arrowPath.append(
    NSBezierPath(
        roundedRect: NSRect(
            x: startX,
            y: centerY - shaftHalfHeight,
            width: max(1, neckX - startX + 1),
            height: shaftHalfHeight * 2
        ),
        xRadius: shaftHalfHeight,
        yRadius: shaftHalfHeight
    )
)

let arrowHeadPath = NSBezierPath()
arrowHeadPath.move(to: NSPoint(x: neckX, y: centerY - headHalfHeight))
arrowHeadPath.line(to: NSPoint(x: tipX, y: centerY))
arrowHeadPath.line(to: NSPoint(x: neckX, y: centerY + headHalfHeight))
arrowHeadPath.close()
arrowPath.append(arrowHeadPath)

let arrowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.23, green: 0.63, blue: 0.98, alpha: 0.92).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.95, alpha: 0.94).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!

NSGraphicsContext.saveGraphicsState()
arrowPath.addClip()
cg.drawLinearGradient(
    arrowGradient,
    start: CGPoint(x: startX, y: centerY),
    end: CGPoint(x: tipX, y: centerY),
    options: []
)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.12).setStroke()
arrowPath.lineWidth = 1
arrowPath.stroke()

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [.compressionFactor: 0.84])!
try data.write(to: out, options: .atomic)
print("generated \(out.path) \(data.count) bytes; panel \(Int(panelWidth))x\(Int(panelHeight))")
