import SwiftUI

// MARK: - Modes

enum ThemeMode: String, CaseIterable, Identifiable {
    /// The restrained warm-editorial look from DESIGN.md. Calm, achromatic, paper-like.
    case light
    /// The dark one. Muted near-monochrome — bone on near-black, no saturated colour.
    case lockedIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .lockedIn: return "Locked In"
        }
    }

    var blurb: String {
        switch self {
        case .light: return "Warm paper. Quiet."
        case .lockedIn: return "Muted near-black. Low contrast."
        }
    }

    /// Maps the retired "darkEdgy" and "dark" values onto Locked In so an existing
    /// preference doesn't silently snap back to Light.
    init?(storedValue: String?) {
        switch storedValue {
        case "darkEdgy", "dark": self = .lockedIn
        case let value?: self.init(rawValue: value)
        default: return nil
        }
    }
}

// MARK: - Settings shared with the widget

/// Settings the widget also needs to read, so they live in the App Group's defaults
/// rather than the app's private ones.
enum AppSettings {
    static let defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard
    static let themeModeKey = "themeMode"
    /// Hides everything that isn't today. Deliberately separate from the theme so a dark
    /// look doesn't force you to give up the upcoming list (and with it, banking days).
    static let focusModeKey = "focusMode"

    static var themeMode: ThemeMode {
        ThemeMode(storedValue: defaults.string(forKey: themeModeKey)) ?? .light
    }

    static var focusMode: Bool {
        defaults.bool(forKey: focusModeKey)
    }
}

// MARK: - Palette

struct ThemePalette {
    // Surfaces
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color

    // Text
    let text: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent — a live UI color in the dark modes, decoration-only in light
    let accent: Color
    let accentSecondary: Color
    let onAccent: Color
    /// Semantic, not decorative: reserved for actions that destroy data. Stays saturated
    /// even in the muted theme, because a warning that blends in isn't a warning.
    let destructive: Color

    // Progress grid
    let gridDone: Color
    let gridMissed: Color
    let gridToday: Color
    let gridFuture: Color
    let gridEmpty: Color

    // Character
    let displayWeight: Font.Weight
    let displayTracking: CGFloat
    let cornerRadius: CGFloat
    /// 0 in every current theme — glows read as decoration, and none of these three want it.
    let glowRadius: CGFloat
    /// Strength of the ambient background wash. 0 means a flat ground.
    let washOpacity: Double
    let isDark: Bool

    /// A soft radial wash behind hero content. Flat when `washOpacity` is 0.
    var ambientWash: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(washOpacity), .clear],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 420
        )
    }
}

// MARK: - Type scale
//
// The scale from DESIGN.md, as tokens. Sizes are chosen from here and nowhere else —
// ad-hoc font sizes are what made the earlier screens drift off-system.

enum TypeScale {
    static let display: CGFloat = 40
    static let heading: CGFloat = 32
    static let headingSm: CGFloat = 26
    static let bodyLg: CGFloat = 20
    static let subheading: CGFloat = 18
    static let body: CGFloat = 16
    static let bodySm: CGFloat = 14
    static let label: CGFloat = 12
    static let caption: CGFloat = 10
}

// MARK: - Radii
//
// DESIGN.md: cards 20, inputs 4, buttons fully pilled. Dark themes tighten cards for a
// harder feel, but every card in a theme uses the same value.

enum Radius {
    static let input: CGFloat = 6
    static let small: CGFloat = 8
    static let control: CGFloat = 12
}

enum Theme {
    // DESIGN.md tokens
    static let eggshell = Color(hex: 0xfdfcfc)
    static let warmTaupe = Color(hex: 0xf5f3f1)
    static let stone = Color(hex: 0xebe8e4)
    static let ink = Color(hex: 0x000000)
    static let graphite = Color(hex: 0x44403b)
    static let smoke = Color(hex: 0x777169)
    /// DESIGN.md's #a59f97 measures ~2.3:1 on eggshell, which fails WCAG AA. Darkened so
    /// it can carry real text; the intent (a footnote voice) is preserved.
    static let ash = Color(hex: 0x807a72)
    static let violetSpark = Color(hex: 0x0447ff)
    static let emberOrange = Color(hex: 0xff4704)

    static func palette(for mode: ThemeMode) -> ThemePalette {
        switch mode {
        case .light:
            return ThemePalette(
                background: eggshell,
                surface: warmTaupe,
                surfaceRaised: eggshell,
                border: stone,
                text: ink,
                textSecondary: smoke,
                textTertiary: ash,
                accent: ink,
                accentSecondary: emberOrange,
                onAccent: .white,
                destructive: Color(hex: 0xc0392b),
                gridDone: ink,
                gridMissed: emberOrange.opacity(0.55),
                gridToday: ink,
                gridFuture: stone,
                gridEmpty: warmTaupe,
                displayWeight: .light,
                displayTracking: -0.02,
                cornerRadius: 20,
                glowRadius: 0,
                washOpacity: 0,
                isDark: false
            )

        // Near-monochrome. "Accent" here is just bone-white — the discipline is that there
        // is no colour to look at, and the UI hides everything that isn't today. Tight
        // radii and regular weight keep it precise rather than shouty.
        case .lockedIn:
            return ThemePalette(
                background: Color(hex: 0x0e0e0e),
                surface: Color(hex: 0x151515),
                surfaceRaised: Color(hex: 0x1a1a1a),
                border: Color(hex: 0x272727),
                text: Color(hex: 0xededec),
                textSecondary: Color(hex: 0x8c8c8a),
                textTertiary: Color(hex: 0x5f5f5d),
                accent: Color(hex: 0xd4d1c9),
                accentSecondary: Color(hex: 0x8a7f6a),
                onAccent: Color(hex: 0x0e0e0e),
                destructive: Color(hex: 0xe0574a),
                gridDone: Color(hex: 0xd4d1c9),
                gridMissed: Color(hex: 0x413a30),
                gridToday: Color(hex: 0xffffff),
                gridFuture: Color(hex: 0x1c1c1c),
                gridEmpty: Color(hex: 0x141414),
                displayWeight: .regular,
                displayTracking: -0.03,
                cornerRadius: 6,
                glowRadius: 0,
                washOpacity: 0,
                isDark: true
            )
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - Environment

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = Theme.palette(for: .light)
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - Type

extension View {
    /// Display type that takes on each theme's character: light and airy, bold, or
    /// heavy-and-shouting.
    func displayStyle(_ palette: ThemePalette, size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: palette.displayWeight))
            .tracking(size * palette.displayTracking)
            .foregroundStyle(palette.text)
    }

    /// Small all-caps section label. Uppercasing happens here, so call sites pass normal
    /// sentence-case strings rather than pre-shouting them.
    func labelStyle(_ palette: ThemePalette) -> some View {
        self
            .font(.system(size: TypeScale.label, weight: .semibold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(palette.textSecondary)
    }

    /// Body copy. Uses `textSecondary`, never `textTertiary` — tertiary is for metadata
    /// fragments only, where it can't fail a contrast check on real sentences.
    func bodyStyle(_ palette: ThemePalette, size: CGFloat = TypeScale.body) -> some View {
        self
            .font(.system(size: size))
            .foregroundStyle(palette.textSecondary)
    }
}

// MARK: - Controls

struct FilledPillButtonStyle: ButtonStyle {
    let palette: ThemePalette
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        // A disabled button reads as "not yet", not as broken: the accent stays, dimmed,
        // and the label keeps enough contrast to be legible.
        let fill = isDisabled ? palette.accent.opacity(0.28) : palette.accent
        return configuration.label
            .font(.system(size: TypeScale.body, weight: .semibold))
            .foregroundStyle(isDisabled ? palette.textSecondary : palette.onAccent)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(fill)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct OutlinePillButtonStyle: ButtonStyle {
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TypeScale.body, weight: .medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(palette.surfaceRaised)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A bare scale-on-press, for custom-chrome buttons (cards, chips) that shouldn't get a pill
/// background but still need to feel pressed rather than just tapped — the same feedback
/// `FilledPillButtonStyle`/`OutlinePillButtonStyle` already give their own controls.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ShippedTextFieldStyle: TextFieldStyle {
    let palette: ThemePalette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            // On macOS, a custom TextFieldStyle body doesn't fully suppress AppKit's native
            // bezel — the field kept a white background under our dark palette's text,
            // which is why it went unreadable in Locked In. Forcing `.plain` first strips
            // that native chrome so our own background/border are the only ones drawn.
            .textFieldStyle(.plain)
            .font(.system(size: TypeScale.subheading))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(palette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.input))
            .overlay(RoundedRectangle(cornerRadius: Radius.input).stroke(palette.border, lineWidth: 1))
    }
}

// MARK: - Containers

struct ThemedCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: { content })
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(palette.border, lineWidth: palette.isDark ? 1 : 0)
            )
    }
}

struct HairlineDivider: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }
}

struct ScreenBackground: ViewModifier {
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    palette.background
                    palette.ambientWash.ignoresSafeArea()
                }
                .ignoresSafeArea()
            )
            .scrollContentBackground(.hidden)
            .preferredColorScheme(palette.isDark ? .dark : .light)
            .tint(palette.accent)
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
