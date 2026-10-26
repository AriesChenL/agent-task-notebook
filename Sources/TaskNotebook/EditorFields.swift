import SwiftUI

struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct EditorField: View {
    let title: String
    @Binding var text: String
    var multiline = false
    @FocusState private var focused: Bool
    init(_ title: String, text: Binding<String>, multiline: Bool = false) {
        self.title = title; self._text = text; self.multiline = multiline
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Group {
                if multiline {
                    TextField("填写" + title, text: $text, axis: .vertical).lineLimit(2...5)
                } else {
                    TextField("填写" + title, text: $text)
                }
            }.textFieldStyle(.plain).font(.system(size: 13)).multilineTextAlignment(.leading)
                .focused($focused).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.accentColor.opacity(0.65) : .primary.opacity(0.09), lineWidth: 1))
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
