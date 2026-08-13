import SwiftUI

/// Motion pieces adapted from componentry.dev. Their library is cursor-driven web effects;
/// these are the ones that translate to touch — an animated gradient, a grain/dither
/// overlay, and a tap ripple.
enum Motion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let stagger = 0.045
}

// MARK: - Animated gradient

/// Two accent blobs drifting behind content. Replaces a flat background with something
/// that quietly moves. Skipped in light mode, where the design calls for paper.
struct AnimatedGradientBackground: View {
    let palette: ThemePalette
    @State private var drift = false

    var body: some View {
        ZStack {
            palette.background

            if palette.washOpacity > 0 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.accent.opacity(0.38), .clear],
                            center: .center, startRadius: 0, endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: drift ? 110 : -60, y: drift ? -240 : -150)
                    .blur(radius: 40)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.accentSecondary.opacity(0.22), .clear],
                            center: .center, startRadius: 0, endRadius: 220
                        )
                    )
                    .frame(width: 420, height: 420)
                    .offset(x: drift ? -130 : 90, y: drift ? 300 : 380)
                    .blur(radius: 50)
            }
        }
        .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: drift)
        .onAppear { drift = true }
        .ignoresSafeArea()
    }
}

// MARK: - Dither / grain

/// A static noise texture at low opacity. Keeps large flat gradients from banding and
/// gives the dark themes a printed feel.
struct GrainOverlay: View {
    var opacity: Double = 0.05

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5eed
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) % 1000) / 1000
            }
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let value = next()
                    if value > 0.55 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: 1, height: 1)),
                            with: .color(.white.opacity(value * 0.5))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Skeletons

/// A shimmering placeholder block. Used while a plan is being generated so the wait shows
/// the shape of what's coming instead of an anonymous spinner.
struct SkeletonBlock: View {
    let palette: ThemePalette
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = Radius.small

    @State private var phase: CGFloat = -1

    var body: some View {
        // Derived from the text colour, not a surface token: in light mode `surfaceRaised`
        // and `background` are both eggshell, so a surface-filled skeleton is invisible.
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(palette.text.opacity(palette.isDark ? 0.11 : 0.09))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            palette.text.opacity(palette.isDark ? 0.09 : 0.06),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.55)
                    .offset(x: phase * geometry.size.width * 1.6)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

/// The plan-shaped skeleton: a date stub and a task line per row.
struct PlanSkeletonList: View {
    let palette: ThemePalette
    var rows: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    SkeletonBlock(palette: palette, height: 12, width: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(
                            palette: palette,
                            height: 13,
                            width: index % 3 == 0 ? 210 : nil
                        )
                        if index % 2 == 0 {
                            SkeletonBlock(palette: palette, height: 13, width: 130)
                        }
                    }
                }
                .opacity(1.0 - Double(index) * 0.1)
            }
        }
    }
}

// MARK: - Ripple

/// Expanding ring from the touch point, fired by bumping `trigger`.
struct RippleEffect: ViewModifier {
    let color: Color
    var trigger: Int

    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            )
            .onChange(of: trigger) { _, _ in
                scale = 0.2
                opacity = 0.6
                withAnimation(.easeOut(duration: 0.55)) {
                    scale = 1.9
                    opacity = 0
                }
            }
    }
}

extension View {
    func ripple(color: Color, trigger: Int) -> some View {
        modifier(RippleEffect(color: color, trigger: trigger))
    }

    /// Fades and lifts content in, offset by its position in a list.
    func staggeredEntrance(index: Int, visible: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .animation(
                Motion.settle.delay(Double(index) * Motion.stagger),
                value: visible
            )
    }
}
