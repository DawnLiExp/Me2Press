//
//  EPUBBookView.swift
//  Me2Press
//
//  View for EPUB to AZW3 conversion queue.
//

import SwiftUI
import UniformTypeIdentifiers

struct EPUBBookView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger
    @State private var viewModel = EPUBBookViewModel()
    @State private var isTargeted = false

    init() {}

    var body: some View {
        Group {
            if viewModel.isConverting {
                ConversionProgressView(progress: viewModel.progress) {
                    viewModel.stopConversion()
                }
                .transition(.opacity)
            } else {
                EPUBFileListView(viewModel: viewModel, isTargeted: $isTargeted)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.isConverting)
    }
}

// MARK: - EPUBFileListView

private struct EPUBFileListView: View {
    @Bindable var viewModel: EPUBBookViewModel
    @Binding var isTargeted: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)

                            Text(LocalizedStringResource("tab.epubbook"))
                                .font(.system(size: 18, weight: .bold))

                            Text("AZW3")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }

                        Text(String(localized: "label.epub_desc"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
                .padding(.horizontal, 24)

            // ── EPUB queue ────────────────────────────────────────────────

            FileQueueView(
                items: viewModel.items,
                isTargeted: $isTargeted,
                headerLabel: "label.pending_files",
                countLabel: "label.books_count",
                rowIcon: "book.fill",
                rowTint: .orange,
                emptyIcon: "book.fill",
                emptyTitle: "label.drag_epub_files",
                emptySubtitle: "label.batch_drag_desc",
                onClearAll: viewModel.clearAll,
                onRemove: viewModel.remove,
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                accepts: { $0.pathExtension.lowercased() == "epub" },
                onDropped: { await viewModel.add($0) },
                onMove: viewModel.move
            )

            // ── Convert button ─────────────────────────────────────────────

            HStack {
                Spacer()
                ConvertStopButton(
                    isConverting: false,
                    isDisabled: viewModel.items.isEmpty || !settings.isKindleGenReady
                ) {
                    viewModel.startConversion(appSettings: settings, logger: logger)
                }
                Spacer()
            }
            .padding(24)
        }
    }
}
