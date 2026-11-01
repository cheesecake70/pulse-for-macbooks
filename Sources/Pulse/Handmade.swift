import SwiftUI

/// One silhouette per mood, drawn as smooth curves in a unit square.
struct Silhouette: Shape {
    let band: Band

    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        switch band {
        case .good:
            // A plump heart: a soft dip on top, full cheeks, rounded bottom.
            p.move(to: pt(0.5, 0.16))
            p.addCurve(to: pt(0.97, 0.3), control1: pt(0.62, 0.0), control2: pt(0.97, 0.02))
            p.addCurve(to: pt(0.58, 0.97), control1: pt(0.97, 0.6), control2: pt(0.8, 0.9))
            p.addCurve(to: pt(0.4, 0.97), control1: pt(0.52, 1.0), control2: pt(0.46, 1.0))
            p.addCurve(to: pt(0.03, 0.3), control1: pt(0.2, 0.9), control2: pt(0.03, 0.6))
            p.addCurve(to: pt(0.5, 0.16), control1: pt(0.03, 0.02), control2: pt(0.38, 0.0))
        case .okay:
            // A little jelly: a dome with three soft scallops underneath.
            p.move(to: pt(0.04, 0.5))
            p.addCurve(to: pt(0.96, 0.5), control1: pt(0.04, -0.1), control2: pt(0.96, -0.1))
            p.addCurve(to: pt(0.88, 0.9), control1: pt(0.98, 0.7), control2: pt(0.96, 0.9))
            p.addCurve(to: pt(0.68, 0.84), control1: pt(0.82, 0.9), control2: pt(0.76, 0.84))
            p.addCurve(to: pt(0.5, 0.96), control1: pt(0.62, 0.84), control2: pt(0.58, 0.96))
            p.addCurve(to: pt(0.32, 0.84), control1: pt(0.42, 0.96), control2: pt(0.38, 0.84))
            p.addCurve(to: pt(0.12, 0.9), control1: pt(0.24, 0.84), control2: pt(0.18, 0.9))
            p.addCurve(to: pt(0.04, 0.5), control1: pt(0.04, 0.9), control2: pt(0.02, 0.7))
        case .poor:
            // A tired drop: a soft point up top, sagging shoulders, a heavy bottom.
            p.move(to: pt(0.46, 0.04))
            p.addCurve(to: pt(0.94, 0.5), control1: pt(0.7, 0.02), control2: pt(0.94, 0.22))
            p.addCurve(to: pt(0.6, 0.98), control1: pt(0.94, 0.78), control2: pt(0.82, 0.98))
            p.addCurve(to: pt(0.06, 0.62), control1: pt(0.3, 0.98), control2: pt(0.06, 0.9))
            p.addCurve(to: pt(0.46, 0.04), control1: pt(0.06, 0.3), control2: pt(0.22, 0.06))
        }
        p.closeSubpath()
        return p
    }
}

/// The Pulse character. Its mood follows the health band.
struct Buddy: View {
    let band: Band
    var size: CGFloat = 110
    var running = true
    @State private var hops = 0
    @State private var hovering = false
    /// Where the pointer is, from -1 to 1 across the face; nil when not hovering.
    @State private var look: CGPoint? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let paused = !running || reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let t = paused ? 0.4 : context.date.timeIntervalSinceReferenceDate
            let breath = sin(t * 2 * .pi / band.beat)
            let sway = sin(t * 2 * .pi / (band.beat * 1.9)) * (band == .good ? 3.0 : 1.5)
            let blink = band != .good && !hovering && t.truncatingRemainder(dividingBy: 4.1) < 0.12
            let wiggle = hovering ? sin(t * 2 * .pi / 0.5) * 2.0 : 0
            ZStack {
                Silhouette(band: band).fill(band.color)
                Canvas { canvas, area in drawFace(&canvas, area.width, blink: blink) }
            }
            .frame(width: size, height: size * 0.92)
            .scaleEffect(x: 1 + breath * 0.02, y: 1 - breath * 0.02, anchor: .bottom)
            .rotationEffect(.degrees(sway + wiggle + Double(look?.x ?? 0) * 4), anchor: .bottom)
        }
        .scaleEffect(hovering ? 1.08 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hovering)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovering = true
                look = CGPoint(x: max(-1, min(1, (point.x / size - 0.5) * 2)),
                               y: max(-1, min(1, (point.y / (size * 0.92) - 0.5) * 2)))
            case .ended:
                hovering = false
                look = nil
            }
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: hops) { view, y in
            view.offset(y: y)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-16, duration: 0.18)
                SpringKeyframe(0, duration: 0.35, spring: .bouncy)
            }
        }
        .onTapGesture { hops += 1 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.mood)
    }

    private func drawFace(_ canvas: inout GraphicsContext, _ w: CGFloat, blink: Bool) {
        let h = w * 0.92
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let style = StrokeStyle(lineWidth: w * 0.022, lineCap: .round, lineJoin: .round)
        let gaze = CGPoint(x: (look?.x ?? 0) * w * 0.02, y: (look?.y ?? 0) * w * 0.015)
        let eyeY = h * 0.47 + gaze.y
        let left = w * 0.38 + gaze.x, right = w * 0.62 + gaze.x

        func stroke(_ points: [CGPoint]) {
            var p = Path()
            p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
            canvas.stroke(p, with: ink, style: style)
        }
        func curve(_ x: CGFloat, _ y: CGFloat, _ half: CGFloat, _ lift: CGFloat) {
            var p = Path()
            p.move(to: CGPoint(x: x - half, y: y))
            p.addQuadCurve(to: CGPoint(x: x + half, y: y), control: CGPoint(x: x, y: y + lift))
            canvas.stroke(p, with: ink, style: style)
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ colour: GraphicsContext.Shading = ink) {
            canvas.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: colour)
        }

        switch band {
        case .good:
            // Closed, happy eyes drawn as little carets, like the reference.
            stroke([CGPoint(x: left - w * 0.04, y: eyeY + w * 0.02), CGPoint(x: left, y: eyeY - w * 0.025), CGPoint(x: left + w * 0.04, y: eyeY + w * 0.02)])
            stroke([CGPoint(x: right - w * 0.04, y: eyeY + w * 0.02), CGPoint(x: right, y: eyeY - w * 0.025), CGPoint(x: right + w * 0.04, y: eyeY + w * 0.02)])
            curve(w / 2, h * 0.6, w * 0.05, w * 0.07)
            dot(left - w * 0.1, eyeY + w * 0.1, w * 0.035, .color(Color(hex: 0xF08A98).opacity(0.55)))
            dot(right + w * 0.1, eyeY + w * 0.1, w * 0.035, .color(Color(hex: 0xF08A98).opacity(0.55)))
        case .okay:
            if hovering {
                // Perks up: wide eyes and a small open smile.
                dot(left, eyeY, w * 0.03)
                dot(right, eyeY, w * 0.03)
                dot(left + w * 0.008, eyeY - w * 0.008, w * 0.009, .color(.white))
                dot(right + w * 0.008, eyeY - w * 0.008, w * 0.009, .color(.white))
                curve(w / 2, h * 0.58, w * 0.04, w * 0.06)
            } else if blink {
                curve(left, eyeY, w * 0.025, 0)
                curve(right, eyeY, w * 0.025, 0)
            } else {
                dot(left, eyeY, w * 0.022)
                dot(right, eyeY, w * 0.022)
            }
            curve(w / 2, h * 0.58, w * 0.035, 0)
        case .poor:
            if hovering {
                // A little comfort: eyes open, mouth flat, tear gone.
                dot(left, eyeY, w * 0.026)
                dot(right, eyeY, w * 0.026)
                curve(w / 2, h * 0.62, w * 0.04, 0)
                return
            }
            curve(left, eyeY, w * 0.045, w * 0.045)
            curve(right, eyeY, w * 0.045, w * 0.045)
            curve(w / 2, h * 0.62, w * 0.045, -w * 0.05)
            var tear = Path()
            tear.addRoundedRect(in: CGRect(x: right + w * 0.055, y: eyeY + w * 0.03, width: w * 0.022, height: w * 0.09),
                                cornerSize: CGSize(width: w * 0.011, height: w * 0.011))
            canvas.fill(tear, with: .color(.white))
        }
    }
}

struct SoftToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Theme.motion) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Theme.mint : Theme.line).frame(width: 36, height: 20)
                    Circle().fill(.white).frame(width: 14, height: 14).padding(3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A still, small version of the character for rows and headers.
struct MiniBuddy: View {
    let band: Band
    var size: CGFloat = 22
    var body: some View {
        Buddy(band: band, size: size, running: false)
            .allowsHitTesting(false)
    }
}
