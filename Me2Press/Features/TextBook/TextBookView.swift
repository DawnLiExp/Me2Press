//
//  TextBookView.swift
//  Me2Press
//

import SwiftUI
import UniformTypeIdentifiers

struct TextBookView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger
    let viewModel: TextBookViewModel
    @State private var isTargeted = false

    var body: some View {
        Group {
            if viewModel.isConverting {
                ConversionProgressView(progress: viewModel.progress, isStopping: viewModel.isStopping) {
                    viewModel.stopConversion()
                }
            } else if viewModel.progress.isFinished {
                ConversionResultView(progress: viewModel.progress, requiresKindleGen: viewModel.outputFormat == .azw3, onDismiss: {
                    viewModel.progress.reset()
                }, onRetry: {
                    viewModel.retryFailed(appSettings: settings, logger: logger)
                })
            } else {
                TextBookFileListView(viewModel: viewModel, isTargeted: $isTargeted)
                }
        }
    }
}

// MARK: - TextBookFileListView

private struct TextBookFileListView: View {
    @Bindable var viewModel: TextBookViewModel
    @Binding var isTargeted: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header / Options ──────────────────────────────────────────

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 24) {
                    CoverDropZone(coverURL: $viewModel.coverImageURL)
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)

                            Text(LocalizedStringResource("tab.textbook"))
                                .font(.system(size: 18, weight: .bold))
                        }
                        .padding(.bottom, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringResource("format.output"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            Picker(String(localized: "format.output"), selection: $viewModel.outputFormat) {
                                ForEach(OutputFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                        }

                        Toggle(String(localized: "option.indent"), isOn: $viewModel.indentParagraph)
                            .font(.system(size: 13))

                        Toggle(String(localized: "option.keep_line_breaks"), isOn: $viewModel.keepLineBreaks)
                            .font(.system(size: 13))
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

            // ── TXT queue ─────────────────────────────────────────────────

            FileQueueView(
                items: viewModel.items,
                isTargeted: $isTargeted,
                isImporting: $viewModel.isImporting,
                inputTypes: [.plainText],
                headerLabel: "label.pending_files",
                countLabel: "label.books_count",
                rowIcon: "doc.text.fill",
                rowTint: .blue,
                emptyIcon: "doc.badge.plus",
                emptyTitle: "label.drag_txt_files",
                emptySubtitle: "label.batch_drag_desc",
                onClearAll: viewModel.clearAll,
                onRemove: viewModel.remove,
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                accepts: { $0.pathExtension.lowercased() == "txt" },
                onDropped: { await viewModel.add($0) },
                onMove: viewModel.move
            )

            KindleGenRequirementView(isRequired: viewModel.outputFormat == .azw3)
                .padding(.horizontal, 24)

            // ── Convert button ─────────────────────────────────────────────

            HStack {
                Spacer()
                ConvertStopButton(
                    isConverting: false,
                    isDisabled: viewModel.isImporting || viewModel.items.isEmpty ||
                        (viewModel.outputFormat == .azw3 && !settings.isKindleGenReady)
                ) {
                    viewModel.startConversion(appSettings: settings, logger: logger)
                }
                Spacer()
            }
            .padding(24)
        }
    }
}
