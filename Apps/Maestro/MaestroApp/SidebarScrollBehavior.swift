import SwiftUI

/// Keep the compact navigation list stationary when it fits, and avoid a scroll
/// edge overlay crossing the custom toolbar when the window is small enough to scroll.
struct SidebarScrollBehavior: ViewModifier {
    func body(content: Content) -> some View {
        // Xcode 16 / Swift 6.1 has no declaration for the Tahoe-only modifier.
        // Keep both SDK-time and runtime gates; Tahoe retains its current style.
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            content.scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
#else
        content.scrollBounceBehavior(.basedOnSize, axes: .vertical)
#endif
    }
}
