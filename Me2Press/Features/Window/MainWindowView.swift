//
//  MainWindowView.swift
//  Me2Press
//
//  Main application window layout: fixed sidebar + fixed content + flexible log panel.
//

import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .comic
    @State private var showLog: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Left — Sidebar (fixed 220pt)

            SidebarView(selectedTab: $selectedTab, showLog: $showLog)
                .frame(width: 220)
                .background(.regularMaterial)

            Divider()
                .opacity(0.5)

            // MARK: Center — Content (fixed when log visible, fills window otherwise)

            Group {
                switch selectedTab {
                case .textbook:
                    TextBookView()
                case .comic:
                    ComicBookView()
                case .epubbook:
                    EPUBBookView()
                }
            }
            // Cap content width so the log panel always receives the remaining space;
            // uncapped when the log panel is hidden.
            .frame(minWidth: 380, maxWidth: showLog ? 520 : .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            // MARK: Right — Log panel (flexible, only log column stretches)

            if showLog {
                Divider()
                    .opacity(0.5)

                LogView()
                    .frame(minWidth: 260)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(WindowDragArea())
    }
}
