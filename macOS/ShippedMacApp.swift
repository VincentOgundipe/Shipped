import SwiftUI
import SwiftData
import ServiceManagement
import AppKit

@main
struct ShippedMacApp: App {
    @AppStorage(AppSettings.themeModeKey, store: AppSettings.defaults)
    private var themeModeRaw = ThemeMode.light.rawValue

    @StateObject private var status = CheckInStatus()

    init() {
        ThemeSnapshotInstaller.install()
        // SwiftUI's `.preferredColorScheme` only repaints our own views. Every native
        // AppKit-bridged control (DatePicker's box, Picker's chrome, a text field's
        // bezel) keeps drawing in whatever appearance the app actually has — which
        // defaulted to Light regardless of the in-app theme, so their own text stayed
        // dark against our dark backgrounds. Setting NSApp.appearance directly is what
        // actually flips those controls.
        AppAppearance.apply(ThemeMode(storedValue: AppSettings.defaults.string(forKey: AppSettings.themeModeKey)) ?? .light)
    }

    private var palette: ThemePalette {
        Theme.palette(for: ThemeMode(storedValue: themeModeRaw) ?? .light)
    }

    var body: some Scene {
        // The real window — what opens from the dock.
        WindowGroup("Shipped") {
            MacRootView()
                .environmentObject(status)
                .environment(\.themePalette, palette)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(palette.isDark ? .dark : .light)
                .onChange(of: themeModeRaw) { _, newValue in
                    AppAppearance.apply(ThemeMode(storedValue: newValue) ?? .light)
                }
        }
        .modelContainer(SharedStore.container)
        .defaultSize(width: 940, height: 640)

        // The always-there nudge, kept alongside the window.
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(status)
                .environment(\.themePalette, palette)
                .modelContainer(SharedStore.container)
        } label: {
            MenuBarLabel(isCheckedIn: status.isCheckedInToday)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Template image so macOS tints it for light/dark menu bars. Pulses while today is still
/// unchecked — the "hops on your toolbar" behaviour.
private struct MenuBarLabel: View {
    let isCheckedIn: Bool
    @State private var pulsing = false

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .opacity(isCheckedIn ? 1.0 : (pulsing ? 0.45 : 1.0))
            .animation(
                isCheckedIn
                    ? .default
                    : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = !isCheckedIn }
            .onChange(of: isCheckedIn) { _, checked in
                pulsing = !checked
            }
    }
}

/// Flips the whole app's real AppKit appearance, not just SwiftUI's environment colour
/// scheme, so native controls repaint correctly too.
@MainActor
enum AppAppearance {
    static func apply(_ mode: ThemeMode) {
        // `NSApp` is AppKit's implicitly-unwrapped global and isn't populated this early in
        // the SwiftUI App lifecycle — calling it from `init()` crashed with exactly the nil
        // force-unwrap this comment is now warning about. `NSApplication.shared` is the same
        // instance but initializes lazily on first access, so it's safe here.
        NSApplication.shared.appearance = Theme.palette(for: mode).isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }
}

/// Registers the app to launch at login. Without this the menu bar pulse — the whole point
/// of the Mac app being always-there — silently stops existing after a restart.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Non-fatal: the app still works, it just won't auto-start.
            print("[LoginItem] \(error.localizedDescription)")
        }
    }
}

@MainActor
final class CheckInStatus: ObservableObject {
    @Published var isCheckedInToday = false

    init() {
        refresh()
    }

    func refresh() {
        let context = ModelContext(SharedStore.container)
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let goal = try? context.fetch(descriptor).first else {
            isCheckedInToday = false
            return
        }
        isCheckedInToday = goal.isDoneForToday
    }
}
