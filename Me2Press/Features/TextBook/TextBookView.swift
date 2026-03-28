//
//  TextBookView.swift
//  Me2Press
//

import SwiftUI
import UniformTypeIdentifiers

struct TextBookView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger
    @State private var viewModel = TextBookViewModel()
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
                TextBookFileListView(viewModel: viewModel, isTargeted: $isTargeted)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.isConverting)
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

                            HStack(spacing: 4) {
                                ForEach(OutputFormat.allCases) { format in
                                    let isSelected = viewModel.outputFormat == format
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            viewModel.outputFormat = format
                                        }
                                    } label: {
                                        Text(format.rawValue)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? .white : .secondary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 5)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
                onDropped: viewModel.add,
                onMove: viewModel.move
            )

            // ── Convert button ─────────────────────────────────────────────

            HStack {
                Spacer()
                ConvertStopButton(
                    isConverting: false,
                    isDisabled: viewModel.items.isEmpty ||
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

// MARK: - CoverDropZone

private struct CoverDropZone: View {
    @Binding var coverURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )

            if let url = coverURL, let image = NSImage(contentsOf: url) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        withAnimation { coverURL = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "label.custom_cover"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                for provider in providers {
                    if let url = try? await loadFileURL(from: provider),
                       ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
                    {
                        withAnimation { coverURL = url }
                        // Accept only the first valid image; ignore subsequent items in the drop.
                        break
                    }
                }
            }
            return true
        }
    }
}
