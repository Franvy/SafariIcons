import SwiftUI

struct StandardIconBox<Content: View>: View {
    let size: CGFloat
    let backgroundColor: Color
    let content: Content

    init(size: CGFloat, backgroundColor: Color = .clear, @ViewBuilder content: () -> Content) {
        self.size = size
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    private var cornerRadius: CGFloat {
        IconBoxGeometry.cornerRadius(for: size)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)

            content
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
