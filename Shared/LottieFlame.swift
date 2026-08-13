import SwiftUI

#if LOTTIE_LINKED
import Lottie

/// Plays a bundled Lottie animation. Guarded by the LOTTIE_LINKED compilation condition
/// (set only on targets that actually link the package) rather than `canImport(Lottie)` —
/// the widget extension doesn't link Lottie, since WidgetKit renders static snapshots and an
/// animation library there would be weight that never plays, but `canImport` can still
/// resolve true for it purely because the module is visible elsewhere in the project, which
/// compiles fine and then fails at link time with missing symbols.
struct LottieAnimationView: View {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var speed: CGFloat = 1
    /// When set, plays once from the start and then holds on the last frame.
    var playOnceTrigger: Int? = nil

    var body: some View {
        LottieView(animation: .named(name))
            .configure { view in
                view.contentMode = .scaleAspectFit
                view.backgroundBehavior = .pauseAndRestore
            }
            .playing(loopMode: loopMode)
            .animationSpeed(speed)
            .id(playOnceTrigger ?? 0)
    }
}
#endif

/// The streak flame. Uses the Lottie fire when it's available and animation is possible,
/// and falls back to a drawn flame in the widget.
///
/// Intensity is carried by scale, speed, and saturation rather than by fill height — the
/// Lottie art has its own baked-in colours, so the level has to read some other way.
struct StreakFlame: View {
    let level: Int
    let palette: ThemePalette
    var size: CGFloat = 34
    var celebrateTrigger: Int = 0
    /// False in widgets, where nothing can animate.
    var animated: Bool = true

    @State private var pop: CGFloat = 1

    private var speed: CGFloat { 0.55 + CGFloat(level) * 0.16 }
    private var levelScale: CGFloat { 0.82 + CGFloat(level) * 0.045 }
    private var saturation: Double { level == 0 ? 0 : 0.55 + Double(level) * 0.11 }

    var body: some View {
        Group {
            #if LOTTIE_LINKED
            if animated {
                LottieAnimationView(name: "fire", speed: speed)
                    .frame(width: size * 1.5, height: size * 1.5)
                    .saturation(saturation)
                    .opacity(level == 0 ? 0.34 : 1)
            } else {
                DrawnFlame(level: level, palette: palette, size: size)
            }
            #else
            DrawnFlame(level: level, palette: palette, size: size)
            #endif
        }
        .frame(width: size, height: size)
        .scaleEffect(pop * levelScale)
        .onChange(of: celebrateTrigger) { _, _ in
            guard animated else { return }
            celebrate()
        }
        .accessibilityLabel("Streak intensity \(level) of 4")
    }

    /// Spring overshoot on earn, the way Duolingo punctuates a streak.
    private func celebrate() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.36)) { pop = 1.45 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { pop = 1 }
        }
    }
}

/// Fallback flame for the widget, where Lottie can't run.
struct DrawnFlame: View {
    let level: Int
    let palette: ThemePalette
    let size: CGFloat

    private var fillFraction: CGFloat {
        guard level > 0 else { return 0 }
        return 0.28 + (CGFloat(level) / 4) * 0.72
    }

    var body: some View {
        ZStack {
            FlameShape()
                .fill(palette.border)
            FlameShape()
                .fill(
                    LinearGradient(
                        colors: [Ember.mid, Ember.hot, Ember.tip],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: size * fillFraction)
                }
        }
        .frame(width: size, height: size)
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.50 * w, y: h))
        path.addQuadCurve(
            to: CGPoint(x: 0.04 * w, y: 0.56 * h),
            control: CGPoint(x: 0.00 * w, y: 0.93 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.44 * w, y: 0.00),
            control: CGPoint(x: 0.09 * w, y: 0.16 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.96 * w, y: 0.56 * h),
            control: CGPoint(x: 0.82 * w, y: 0.21 * h)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0.50 * w, y: h),
            control: CGPoint(x: 1.00 * w, y: 0.93 * h)
        )
        path.closeSubpath()
        return path
    }
}

enum Ember {
    static let hot = Color(hex: 0xff7a18)
    static let mid = Color(hex: 0xff4d1a)
    static let tip = Color(hex: 0xffc23d)
}
