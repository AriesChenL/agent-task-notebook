import SwiftUI

/// An inset workspace with a continuous corner, distinct from the window chrome.
struct WorkspacePanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    private let radius: CGFloat = 22
    private var fill: Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.09, blue: 0.11)
            : Color(red: 0.985, green: 0.985, blue: 0.99)
    }
    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.bottom, 10)

    }
}

/// Keep the title bar on the same background as the sidebar and panel gutter.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.apply() }
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.toolbar?.showsBaselineSeparator = false
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

/// One stationary blur layer for the entire shell, rather than one per card.
struct FrostedWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { WindowMaterial() }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
private struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
