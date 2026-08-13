import SwiftUI
import SwiftData

@main
struct ShippedApp: App {
    @AppStorage(AppSettings.themeModeKey, store: AppSettings.defaults)
    private var themeModeRaw = ThemeMode.light.rawValue

    @State private var auth = AuthState()

    init() { ThemeSnapshotInstaller.install() }

    private var palette: ThemePalette {
        Theme.palette(for: ThemeMode(storedValue: themeModeRaw) ?? .light)
    }

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .environment(\.themePalette, palette)
                .animation(.easeInOut(duration: 0.35), value: themeModeRaw)
        }
        .modelContainer(SharedStore.container)
    }
}
