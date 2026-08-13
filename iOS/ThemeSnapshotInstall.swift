import SwiftUI
import UIKit

/// Installs the snapshot provider used by the theme reveal. Lives in the iOS app target
/// rather than Shared because `UIApplication.shared` is unavailable to app extensions, and
/// the widget compiles everything in Shared.
enum ThemeSnapshotInstaller {
    static func install() {
        ThemeSnapshot.provider = {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first
            else { return nil }

            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                // afterScreenUpdates: false captures the frame as it is right now, which is
                // the "old" theme we want to hold still.
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            return Image(uiImage: image)
        }
    }
}
