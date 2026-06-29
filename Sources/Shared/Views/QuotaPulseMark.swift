import SwiftUI

struct QuotaPulseMark: View {
    var size: CGFloat = 18
    var ringColor: Color = .primary
    var pulseColor: Color = Color(red: 0.18, green: 0.86, blue: 0.79)
    var lineWidth: CGFloat?
    var showsPulse: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let strokeWidth = lineWidth ?? max(2, side * 0.13)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = (side - strokeWidth) / 2

            var ring = Path()
            ring.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(130),
                endAngle: .degrees(398),
                clockwise: false
            )
            context.stroke(
                ring,
                with: .color(ringColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )

            let tailAngle = Angle.degrees(42).radians
            let tailStart = CGPoint(
                x: center.x + cos(tailAngle) * radius * 0.55,
                y: center.y + sin(tailAngle) * radius * 0.55
            )
            let tailEnd = CGPoint(
                x: center.x + cos(tailAngle) * radius * 0.93,
                y: center.y + sin(tailAngle) * radius * 0.93
            )
            var tail = Path()
            tail.move(to: tailStart)
            tail.addLine(to: tailEnd)
            context.stroke(
                tail,
                with: .color(ringColor),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt, lineJoin: .round)
            )

            guard showsPulse else { return }

            let pulseWidth = max(1.4, strokeWidth * 0.34)
            let left = center.x - radius
            let top = center.y - radius
            let width = radius * 2
            var pulse = Path()
            let points = [
                CGPoint(x: left + width * 0.27, y: center.y),
                CGPoint(x: left + width * 0.40, y: center.y),
                CGPoint(x: left + width * 0.48, y: top + width * 0.38),
                CGPoint(x: left + width * 0.57, y: top + width * 0.62),
                CGPoint(x: left + width * 0.66, y: top + width * 0.46),
                CGPoint(x: left + width * 0.78, y: top + width * 0.46)
            ]
            pulse.move(to: points[0])
            for point in points.dropFirst() {
                pulse.addLine(to: point)
            }
            context.stroke(
                pulse,
                with: .color(pulseColor),
                style: StrokeStyle(lineWidth: pulseWidth, lineCap: .round, lineJoin: .round)
            )

            let dotRadius = pulseWidth * 0.85
            let dotCenter = points[points.count - 1]
            let dotRect = CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(pulseColor))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
