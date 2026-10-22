import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .comic
    @AppStorage("showLog") private var showLog = true
    @State private var textModel = TextBookViewModel()
    @State private var comicModel = ComicBookViewModel()
    @State private var epubModel = EPUBBookViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedTab: $selectedTab, showLog: $showLog)
                .frame(width: 220)
                .background(.regularMaterial)
            Divider()
            HSplitView {
                Group {
                    switch selectedTab {
                    case .textbook: TextBookView(viewModel: textModel)
                    case .comic: ComicBookView(viewModel: comicModel)
                    case .epubbook: EPUBBookView(viewModel: epubModel)
                    }
                }
                .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                if showLog {
                    LogView()
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(WindowDragArea())
    }
}
