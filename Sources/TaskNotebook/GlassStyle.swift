import SwiftUI

struct WorkspaceBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
    }
}
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 22
    var control = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else if #available(macOS 26.0, *), control {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else if !control {
            // Scrolling surfaces use a static fill: no live backdrop sampling per card.
            content
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.18 : 0.75), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        }
    }
}
extension View {
    func notebookGlass(radius: CGFloat = 22, control: Bool = false) -> some View { modifier(GlassSurface(radius: radius, control: control)) }
}
