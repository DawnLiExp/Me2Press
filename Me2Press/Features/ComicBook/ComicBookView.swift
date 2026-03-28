//
//  ComicBookView.swift
//  Me2Press
//
//  View for comic book conversion settings and queue.
//

import SwiftUI
import UniformTypeIdentifiers

struct ComicBookView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger
    @State private var viewModel = ComicBookViewModel()
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
                ComicFolderListView(viewModel: viewModel, isTargeted: $isTargeted)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.isConverting)
    }
}

// MARK: - ComicFolderListView

private struct ComicFolderListView: View {
    @Bindable var viewModel: ComicBookViewModel
    @Binding var isTargeted: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(LogManager.self) private var logger

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────

            VStack(alignment: .leading, spacing: 20) {
                // Title + description
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.yellow)

                            Text(LocalizedStringResource("tab.comic"))
                                .font(.system(size: 18, weight: .bold))

                            Text("MOBI")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.1))
                                .foregroundStyle(.yellow)
                                .clipShape(Capsule())
                        }

                        Text(String(localized: "label.comic_desc"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Concurrency control — inline for quick adjustment without opening Settings
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)

                        Text(String(localized: "setting.concurrency.label"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(settings.maxConcurrency)")
                            .monospacedDigit()
                            .font(.system(.subheadline, design: .rounded).bold())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Slider(value: Binding(
                        get: { Double(settings.maxConcurrency) },
                        set: { settings.maxConcurrency = Int($0.rounded()) }
                    ), in: Double(AppSettings.concurrencyRange.lowerBound) ... Double(AppSettings.concurrencyRange.upperBound), step: 1)
                        .labelsHidden()
                        .controlSize(.small)
                        .transaction { $0.animation = nil }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(Color(NSColor.windowBackgroundColor))

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 1)
                .padding(.horizontal, 24)

            // ── Image folder queue ────────────────────────────────────────

            FileQueueView(
                items: viewModel.items,
                isTargeted: $isTargeted,
                headerLabel: "label.pending_folders",
                countLabel: "label.folders_count",
                headerTooltip: "label.comic_folder_rule",
                rowIcon: "folder.fill",
                rowTint: .yellow,
                emptyIcon: "folder.badge.plus",
                emptyTitle: "label.drag_image_folders",
                emptySubtitle: "label.comic_folder_desc",
                onClearAll: viewModel.clearAll,
                onRemove: viewModel.remove,
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                accepts: { url in
                    var isDir: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                        && isDir.boolValue
                },
                onDropped: viewModel.add,
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
