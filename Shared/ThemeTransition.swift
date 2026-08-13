import SwiftUI

/// Where the reveal starts from.
enum RevealOrigin: Equatable {
    case point(CGPoint)
    case leadingEdge
}

/// Supplies a still image of the current UI. Installed by each app at launch — it can't live
/// in Shared because the snapshot APIs are unavailable to app extensions, and the widget
/// compiles this file too.
enum ThemeSnapshot {
    static var provider: (() -> Image?)?
}

/// A circular theme reveal modelled on the CSS View Transitions pattern:
///
///  - the *old* frame is captured and held still
///  - the palette swaps underneath immediately, so the live view is already the new theme
///  - the old snapshot is overlaid and a circular hole grows out of the click point
///
/// The earlier version expanded a flat coloured disc over everything and cross-faded, which
/// looked like a blob wiping the screen rather than the new theme being revealed.
@Observable
final class ThemeTransition {
    private(set) var snapshot: Image?
    private(set) var origin: RevealOrigin = .leadingEdge
    /// 0 = hole closed (old frame fully covering), 1 = hole larger than the screen.
    private(set) var progress: CGFloat = 0
    private(set) var isRunning = false

    @MainActor
    func run(to mode: ThemeMode, from origin: RevealOrigin, apply: @escaping () -> Void) {
        guard !isRunning else {
            apply()
            return
        }

        // Capture before the swap; without a snapshot there's nothing to reveal from, so
        // fall back to an instant change rather than faking one.
        guard let captured = ThemeSnapshot.provider?() else {
            apply()
            return
        }

        self.origin = origin
        snapshot = captured
        progress = 0
        isRunning = true

        // Swap underneath the still frame, then open the hole.
        apply()

        withAnimation(.easeInOut(duration: 0.5)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            self.isRunning = false
            self.snapshot = nil
            self.progress = 0
        }
    }
}

struct ThemeRevealOverlay: ViewModifier {
    let transition: ThemeTransition

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                if transition.isRunning, let snapshot = transition.snapshot {
                    let size = geometry.size
                    let center = revealCenter(in: size)
                    // 200vmax equivalent: big enough to clear the furthest corner.
                    let maxRadius = maxDistance(from: center, in: size)

                    snapshot
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .mask {
                            // The old frame, minus a growing circle: the hole is where the
                            // new theme shows through.
                            Rectangle()
                                .fill(.white)
                                .overlay {
                                    Circle()
                                        .frame(
                                            width: maxRadius * 2 * transition.progress,
                                            height: maxRadius * 2 * transition.progress
                                        )
                                        .position(center)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
        }
    }

    private func revealCenter(in size: CGSize) -> CGPoint {
        switch transition.origin {
        case .point(let point): return point
        case .leadingEdge: return CGPoint(x: 0, y: size.height / 2)
        }
    }

    private func maxDistance(from point: CGPoint, in size: CGSize) -> CGFloat {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        return corners.map { hypot($0.x - point.x, $0.y - point.y) }.max()
            ?? max(size.width, size.height)
    }
}

extension View {
    func themeReveal(_ transition: ThemeTransition) -> some View {
        modifier(ThemeRevealOverlay(transition: transition))
    }
}
