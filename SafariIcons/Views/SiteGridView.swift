import SwiftUI

struct SiteGridView: View {
    private static let desiredVisualIconSpacing: CGFloat = 21
    private static let columnSpacing: CGFloat = max(
        0,
        desiredVisualIconSpacing - ((SiteGridCell.layoutWidth - SiteGridCell.iconBoxSize))
    )
    private static let rowSpacing: CGFloat = 12

    let bookmarks: [FavoriteBookmark]
    @Binding var editingBookmarkID: FavoriteBookmark.ID?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: SiteGridCell.layoutWidth,
                maximum: SiteGridCell.layoutWidth
            ),
            spacing: Self.columnSpacing
        )
    ]

    var body: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView(
                "No Favorites",
                systemImage: "star",
                description: Text("Add sites to Favorites in Safari and their icons will appear here.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: Self.rowSpacing) {
                    ForEach(bookmarks) { bookmark in
                        SiteGridCell(bookmark: bookmark, editingBookmarkID: $editingBookmarkID)
                    }
                }
                .padding(24)
                .accessibilityElement(children: .contain)
            }
            .scrollIndicators(.hidden)
        }
    }
}
