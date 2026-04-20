import CoreGraphics

enum IconBoxGeometry {
    static let referenceSize: CGFloat = 72
    static let referenceCornerRadius: CGFloat = 20
    static let referenceGlassSmallInset: CGFloat = 6

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        size * referenceCornerRadius / referenceSize
    }

    static func glassSmallInset(for size: CGFloat) -> CGFloat {
        size * referenceGlassSmallInset / referenceSize
    }
}
