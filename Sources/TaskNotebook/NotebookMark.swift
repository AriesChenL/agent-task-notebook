import SwiftUI

/// A small, monochrome notebook mark for navigation chrome.
struct NotebookMark: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(lineWidth: 1.7)
                    .frame(width: w * 0.76, height: h * 0.84)
                    .offset(x: w * 0.06, y: h * 0.03)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.11))
                    path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.95))
                    path.move(to: CGPoint(x: w * 0.48, y: h * 0.34))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.34))
                    path.move(to: CGPoint(x: w * 0.48, y: h * 0.49))
                    path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.49))
                }.stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
        }
    }
}
