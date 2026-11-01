import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Quiet warm paper, one look in both appearances. Restraint is the whole style.
enum Theme {
    static let width: CGFloat = 320
    static let canvas = Color(hex: 0xFAF7F1)
    static let line = Color(hex: 0xECE8E1)
    static let ink = Color(hex: 0x2E2C2A)
    static let inkSoft = Color(hex: 0x6F6963)
    static let happy = Color(hex: 0xF6BFCB)
    static let normal = Color(hex: 0xBFD9CC)
    static let sad = Color(hex: 0x9DB8E8)
    static let mint = Color(hex: 0xC9E2D1)

    static let motion = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let ringMotion = Animation.spring(response: 0.6, dampingFraction: 0.7)

    /// Space Mono (OFL) is bundled in Resources/Fonts and registered at launch.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular ? "SpaceMono-Regular" : "SpaceMono-Bold", size: size)
    }

    /// Looks beside the executable (dev builds), then inside the app bundle's Resources. It does not use
    /// `Bundle.module`, whose generated accessor stops the app if the resource bundle was moved.
    static func registerFonts() {
        let main = Bundle.main
        let candidates = [
            main.resourceURL?.appendingPathComponent("Fonts"),
            main.resourceURL?.appendingPathComponent("Pulse_Pulse.bundle/Fonts"),
            main.bundleURL.appendingPathComponent("Pulse_Pulse.bundle/Fonts"),
            main.executableURL?.deletingLastPathComponent().appendingPathComponent("Pulse_Pulse.bundle/Fonts"),
        ].compactMap { $0 }
        guard let dir = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum Band {
    case good, okay, poor

    init(score: Int) {
        self = score >= 85 ? .good : score >= 65 ? .okay : .poor
    }

    var color: Color {
        switch self {
        case .good: Theme.happy
        case .okay: Theme.normal
        case .poor: Theme.sad
        }
    }

    var headline: String {
        switch self {
        case .good: "No action needed"
        case .okay: "Could use a little care"
        case .poor: "Your Mac needs you"
        }
    }

    var mood: String {
        switch self {
        case .good: "Pulse is happy"
        case .okay: "Pulse is okay"
        case .poor: "Pulse is sad"
        }
    }

    /// Seconds per breath: calm when healthy, quicker when strained.
    var beat: Double {
        switch self {
        case .good: 3.4
        case .okay: 2.4
        case .poor: 1.6
        }
    }
}

/// Neutral outline that fills with the character's colour on hover. `tint` makes it filled always.
struct PillButton: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.moodColor) private var mood

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, tint: tint, mood: mood)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let tint: Color?
        let mood: Color
        @State private var hovering = false

        var body: some View {
            let filled = tint != nil || hovering
            configuration.label
                .font(Theme.text(13, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    Capsule().fill(filled ? (tint ?? mood) : .clear)
                    Capsule().stroke(Theme.ink.opacity(filled ? 0 : 0.7), lineWidth: 1.2)
                }
                .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.04 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

private struct MoodColorKey: EnvironmentKey {
    static let defaultValue = Theme.happy
}

extension EnvironmentValues {
    /// The current character colour, so buttons can borrow it.
    var moodColor: Color {
        get { self[MoodColorKey.self] }
        set { self[MoodColorKey.self] = newValue }
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(13))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
