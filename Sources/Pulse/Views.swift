import SwiftUI
import PulseCore

struct RootView: View {
    @ObservedObject var store: PulseStore

    var body: some View {
        Group {
            if store.showWelcome {
                WelcomeView(store: store)
            } else if !store.ready {
                CheckingView(store: store)
            } else {
                switch store.route {
                case .home: HomeView(store: store)
                case .details: DetailsView(store: store)
                case .habits: HabitsView(store: store)
                case .settings: SettingsView(store: store)
                case .area(let id): AreaView(store: store, id: id)
                }
            }
        }
        .frame(width: Theme.width)
        .background(Theme.canvas)
        .textCase(.lowercase)
        .environment(\.moodColor, (store.fixes.isEmpty ? Band.good : Band(score: store.score)).color)
    }
}

/// Shown only until the first real reading arrives, so no state is shown that isn't true.
struct CheckingView: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        VStack(spacing: 0) {
            Buddy(band: .okay, size: 76, running: store.isOpen).padding(.top, 28)
            Text("Taking a quick look.")
                .font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                .padding(.top, 16).padding(.bottom, 28)
        }
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.text(13))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .transition(.opacity)
    }
}

/// Small, lowercase, letter-spaced so it recedes behind the content.
struct FooterButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(13))
            .tracking(0.8)
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var store: PulseStore

    var body: some View {
        let band = store.fixes.isEmpty ? Band.good : Band(score: store.score)
        VStack(spacing: 0) {
            Buddy(band: band, size: 76, running: store.isOpen).padding(.top, 28)

            Text(band.headline)
                .font(Theme.text(13, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 16)
            Button { withAnimation(Theme.motion) { store.route = .details } } label: {
                Text("\(store.score)% healthy")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSoft)
                    .underline(true, pattern: .dot, color: Theme.line)
                    .contentTransition(.numericText(value: Double(store.score)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if store.fixes.isEmpty {
                Text(store.justFixedAll ? "All sorted. That feels better." : "Everything's running well.")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 26)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.fixes) { FixRow(store: store, fix: $0) }
                }
                .padding(.top, 22)
            }

            if let toast = store.toast { Toast(text: toast).padding(.top, 14) }

            HStack {
                Button("details") { withAnimation(Theme.motion) { store.route = .details } }
                Spacer()
                Button("settings") { withAnimation(Theme.motion) { store.route = .settings } }
            }
            .buttonStyle(FooterButton())
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
    }
}

struct FixRow: View {
    @ObservedObject var store: PulseStore
    let fix: Fix
    @State private var rowHover = false

    var body: some View {
        let open = store.expanded == fix.id
        let confirming = store.confirming == fix.id
        let working = store.working.contains(fix.id)
        let forcing = store.forceOffer == fix.id
        let waiting = store.acknowledged.contains(fix.id) || working
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fix.title).font(Theme.text(13, .bold)).foregroundStyle(Theme.ink)
                    Text(working ? "waiting for it to close." : waiting ? "cooling down. this goes away soon." : fix.reason)
                        .font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if waiting {
                    MiniBuddy(band: .okay, size: 20)
                } else if !confirming && !forcing {
                    Button(fix.button) { store.primary(fix) }.buttonStyle(PillButton())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !waiting else { return }
                withAnimation(Theme.motion) { store.expanded = open ? nil : fix.id }
            }
            .background(rowHover ? Theme.line.opacity(0.45) : .clear)
            .onHover { rowHover = $0 }
            .animation(.easeOut(duration: 0.15), value: rowHover)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(open ? "hides why" : "shows why")

            if confirming {
                HStack {
                    Text("\(fix.button) now?").font(Theme.text(13)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Cancel") { withAnimation(Theme.motion) { store.confirming = nil } }.buttonStyle(QuietButton())
                    Button("\(fix.button) now") { store.complete(fix) }.buttonStyle(PillButton(tint: Theme.sad))
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
                .transition(.opacity)
            }

            if forcing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("It won't close. Force quit? Unsaved work will be lost.")
                        .font(Theme.text(13)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { store.cancelForce() }.buttonStyle(QuietButton())
                        Button("Force quit") { store.forceQuit(fix) }.buttonStyle(PillButton(tint: Theme.sad))
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
                .transition(.opacity)
            }

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fix.happening).foregroundStyle(Theme.ink)
                    Text(fix.matters).foregroundStyle(Theme.inkSoft)
                    Text(fix.willDo).foregroundStyle(Theme.inkSoft)
                    if fix.snoozable {
                        Button(SnoozeCopy.button(for: fix.id)) { store.snooze(fix) }.buttonStyle(QuietButton()).padding(.leading, -8)
                    }
                }
                .font(Theme.text(13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
            Hairline().padding(.horizontal, 24)
        }
        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.97))))
    }
}

// MARK: - Second level

struct PageHeader: View {
    let title: String
    var band: Band? = nil
    let back: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button(action: { withAnimation(Theme.motion, back) }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft).frame(width: 24, height: 28)
                    Text(title).font(Theme.text(13, .bold)).foregroundStyle(Theme.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Spacer()
            if let band { MiniBuddy(band: band, size: 26).padding(.trailing, 20) }
        }
        .padding(.leading, 14).padding(.top, 14).padding(.bottom, 10)
    }
}

struct DetailsView: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Your Mac", band: store.fixes.isEmpty ? .good : Band(score: store.score)) { store.route = .home }
            ForEach(store.areas) { area in
                Button { withAnimation(Theme.motion) { store.route = .area(area.id) } } label: {
                    HStack(spacing: 10) {
                        MiniBuddy(band: area.level > 0.8 ? .good : area.level > 0.5 ? .okay : .poor, size: 20)
                        Text(area.id).font(Theme.text(13, .bold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(area.status).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 24).frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline().padding(.horizontal, 24)
            }
            Button("good habits") { withAnimation(Theme.motion) { store.route = .habits } }
                .buttonStyle(FooterButton()).padding(.top, 10).padding(.bottom, 12)
        }
    }
}

struct AreaView: View {
    @ObservedObject var store: PulseStore
    let id: String
    var body: some View {
        let area = store.areas.first { $0.id == id }
            ?? Area(id: id, symbol: "", status: "", explain: "", level: 1, numbers: [])
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: area.id) { store.route = .details }
            Text(area.status).font(Theme.text(13, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 24).padding(.top, 8)
            Text(area.explain).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 24).padding(.top, 3)
            VStack(spacing: 0) {
                ForEach(area.numbers, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(row.1).foregroundStyle(Theme.ink).monospacedDigit()
                    }
                    .font(Theme.text(13)).frame(height: 34)
                    Hairline()
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
        }
    }
}

struct HabitsView: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Good habits") { store.route = .details }
            ForEach(Demo.habits, id: \.1) { habit in
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.1).font(Theme.text(13, .bold)).foregroundStyle(Theme.ink)
                    Text(habit.2).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 24).padding(.vertical, 7)
            }
        }
        .padding(.bottom, 14)
    }
}

struct SettingsView: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings") { store.route = .home }
            Toggle("Start when you log in", isOn: $store.startAtLogin).frame(height: 40)
            Hairline()
            Toggle("Tell me when my Mac needs attention", isOn: $store.notify).frame(height: 40)
            Text("Nothing leaves your Mac. Pulse has no account, no tracking, and never connects to the internet.")
                .font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Button("quit pulse") { NSApp.terminate(nil) }.buttonStyle(FooterButton()).padding(.leading, -8).padding(.top, 14)
        }
        .toggleStyle(SoftToggle())
        .font(Theme.text(13)).foregroundStyle(Theme.ink)
        .padding(.horizontal, 24).padding(.bottom, 10)
    }
}

struct WelcomeView: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        VStack(spacing: 0) {
            Buddy(band: .good, size: 76, running: store.isOpen).padding(.top, 28)
            Text("Hi, I'm Pulse").font(Theme.text(13, .bold)).foregroundStyle(Theme.ink).padding(.top, 22)
            Text("I keep an eye on your Mac. If it needs something, I'll say what to do in plain words.")
                .font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36).padding(.top, 6)
            Toggle("Start when you log in", isOn: $store.startAtLogin)
                .toggleStyle(SoftToggle()).font(Theme.text(13)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 36).padding(.top, 24)
            Button("Let's go") { withAnimation(Theme.motion) { store.showWelcome = false } }
                .buttonStyle(PillButton(tint: Theme.happy)).padding(.top, 22)
            Text("Nothing leaves your Mac.").font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                .padding(.top, 10).padding(.bottom, 22)
        }
    }
}
