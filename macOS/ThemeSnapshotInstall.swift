import SwiftUI
import AppKit

/// macOS half of the theme-reveal snapshot provider.
enum ThemeSnapshotInstaller {
    static func install() {
        ThemeSnapshot.provider = {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let contentView = window.contentView
            else { return nil }

            let bounds = contentView.bounds
            guard bounds.width > 1, bounds.height > 1,
                  let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds)
            else { return nil }

            contentView.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return Image(nsImage: image)
        }
    }
}
