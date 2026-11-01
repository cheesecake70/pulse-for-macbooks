import AppKit
import SwiftUI

/// Renders every screen to PNG for design review. Run with `--snapshots <folder>`.
@MainActor
enum Snapshots {
    static func write(to folder: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for (mode, name) in [(NSAppearance.Name.aqua, "light")] {
            NSAppearance(named: mode)?.performAsCurrentDrawingAppearance {
                NSApp?.appearance = NSAppearance(named: mode)
                for (label, setup) in screens {
                    let store = PulseStore(mode: .demo)
                    store.isOpen = false
                    setup(store)
                    let view = RootView(store: store)
                        .environment(\.colorScheme, name == "dark" ? .dark : .light)
                    save(view, to: "\(folder)/\(label)-\(name).png")
                }
            }
        }
    }

    private static let screens: [(String, (PulseStore) -> Void)] = [
        ("1-healthy", { $0.load(.healthy) }),
        ("2-better", { $0.load(.better) }),
        ("3-attention", { $0.load(.attention) }),
        ("4-why", { $0.load(.better); $0.expanded = "chrome" }),
        ("5-confirm", { $0.load(.better); $0.confirming = "restart" }),
        ("6-details", { $0.load(.healthy); $0.route = .details }),
        ("7-numbers", { $0.load(.healthy); $0.route = .area("Battery") }),
        ("8-habits", { $0.load(.healthy); $0.route = .habits }),
        ("9-settings", { $0.load(.healthy); $0.route = .settings }),
        ("10-welcome", { $0.load(.healthy); $0.showWelcome = true }),
    ]

    private static func save<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? png?.write(to: URL(fileURLWithPath: path))
    }

    static func writeIcon(to path: String) {
        save(AppIcon().frame(width: 512, height: 512), to: path)
    }
}

struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 112, style: .continuous).fill(Theme.canvas)
            Buddy(band: .good, size: 340, running: false)
        }
        .frame(width: 512, height: 512)
    }
}
