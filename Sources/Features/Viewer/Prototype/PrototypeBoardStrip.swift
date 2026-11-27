import SwiftUI

/// Penpot's thumbnails panel in the viewer (`viewer/thumbnails.cljs`): the page's boards,
/// in the viewer's order, to jump to one. "n boards" and a close button above a row of
/// previews with the board's name under each; the board on screen is marked. Picking one
/// keeps the panel open, as Penpot does.
struct PrototypeBoardStrip: View {
    @Environment(AppState.self) private var appState
    let boards: [Board]
    let currentID: String?
    let fileID: String
    let revision: Int?
    let teamID: String?
    /// Board id → Penpot's thumbnail media id.
    let thumbnails: [String: String]
    let onSelect: (String) -> Void
    let onClose: () -> Void

    /// Penpot's 132 px previews, smaller for a phone.
    private let side: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(boards.count) boards")
                    .font(.workSans(.footnote))
                    .foregroundStyle(Color.penpotForegroundSecondary)
                Spacer()
                Button(action: onClose) {
                    AppIcon.closeFilled.image
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.penpotForegroundSecondary)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 4) {
                        ForEach(boards, id: \.id) { board in
                            item(board)
                                .id(board.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                // A horizontal scroll view takes all the height it is offered.
                .fixedSize(horizontal: false, vertical: true)
                .onAppear { proxy.scrollTo(currentID, anchor: .center) }
                .onChange(of: currentID) {
                    withAnimation { proxy.scrollTo(currentID, anchor: .center) }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.penpotSurface, ignoresSafeAreaEdges: .bottom)
    }

    private func item(_ board: Board) -> some View {
        let isCurrent = board.id == currentID
        return Button {
            onSelect(board.id)
        } label: {
            VStack(spacing: 4) {
                preview(board)
                    .frame(width: side, height: side)
                    .padding(4)
                    .background(isCurrent ? Color.penpotAccent.opacity(0.2) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                Text(verbatim: board.name)
                    .font(.workSans(.caption))
                    .foregroundStyle(Color.penpotForegroundSecondary)
                    .lineLimit(1)
                    .frame(width: side + 8)
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: board.name))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private func preview(_ board: Board) -> some View {
        if let baseURL = appState.client?.baseURL {
            BoardImage(fileID: fileID, revision: revision, board: board,
                       mediaID: thumbnails[board.id], baseURL: baseURL, teamID: teamID)
        }
    }
}
