//
//  FileQueueView.swift
//  Me2Press
//
//  Generic queue container used by all three conversion tabs.
//  Composes DropHintView (empty state) and FileRowView (item rows)
//  inside a dashed-border drop target.
//  Shows reason-specific rejection banners for unsupported or content-invalid drops,
//  while duplicate items are silently ignored.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileQueueView: View {
    struct FileQueueDropSummary: Sendable {
        let addedCount: Int
        let duplicateCount: Int
        let contentRejectedCount: Int

        static let empty = FileQueueDropSummary(
            addedCount: 0,
            duplicateCount: 0,
            contentRejectedCount: 0
        )
    }

    let items: [URL]
    @Binding var isTargeted: Bool

    // MARK: Labels

    let headerLabel: LocalizedStringResource
    let countLabel: LocalizedStringResource

    var headerTooltip: LocalizedStringResource?

    // MARK: Row appearance

    let rowIcon: String
    let rowTint: Color

    // MARK: Empty state

    let emptyIcon: String
    let emptyTitle: LocalizedStringResource
    let emptySubtitle: LocalizedStringResource
    var contentRejectedMessage: LocalizedStringResource? = nil

    // MARK: Actions

    let onClearAll: () -> Void
    let onRemove: (URL) -> Void
    let onReveal: (URL) -> Void
    /// Validates whether a dropped URL is acceptable for this queue.
    let accepts: (URL) -> Bool
    /// Called with only the accepted URLs after a successful drop.
    /// Returns a summary that distinguishes additions, duplicates, and content rejection.
    let onDropped: ([URL]) async -> FileQueueDropSummary
    /// Optional reorder handler. When provided, rows become drag-reorderable.
    var onMove: ((IndexSet, Int) -> Void)?

    // MARK: Rejection state

    @State private var showRejectionHint = false
    @State private var rejectionMessage: LocalizedStringResource?
    @State private var rejectionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Queue header ───────────────────────────────────────────────

            HStack {
                Text(headerLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)

                if let tooltip = headerTooltip {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .help(Text(tooltip))
                }

                Spacer()

                if !items.isEmpty {
                    Button {
                        withAnimation { onClearAll() }
                    } label: {
                        Text(String(localized: "button.clear_all"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(items.count) ") + Text(countLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // ── Drop zone ──────────────────────────────────────────────────

            ZStack {
                if items.isEmpty {
                    DropHintView(
                        icon: emptyIcon,
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                        isTargeted: isTargeted
                    )
                } else {
                    // IMPORTANT: List is required for .onMove drag-reorder support;
                    // LazyVStack does not support .onMove. Separator and default background
                    // are suppressed to preserve the existing row styling from FileRowView.
                    List {
                        ForEach(items, id: \.self) { item in
                            FileRowView(
                                url: item,
                                icon: rowIcon,
                                tint: rowTint,
                                onRemove: { withAnimation { onRemove(item) } },
                                onReveal: { onReveal(item) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        }
                        .onMove(perform: onMove)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // ── Rejection banner overlay ───────────────────────────────

                if showRejectionHint, let rejectionMessage {
                    RejectionBanner(message: rejectionMessage)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.02))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                        style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 4])
                    )
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                Task { @MainActor in
                    var resolved = [URL]()
                    for provider in providers {
                        if let url = try? await loadFileURL(from: provider) {
                            resolved.append(url)
                        }
                    }

                    let valid = resolved.filter { accepts($0) }
                    let unsupportedCount = resolved.count - valid.count
                    let summary = valid.isEmpty ? .empty : await onDropped(valid)

                    if let rejectionMessage = determineRejectionMessage(
                        unsupportedCount: unsupportedCount,
                        contentRejectedCount: summary.contentRejectedCount
                    ) {
                        triggerRejectionHint(message: rejectionMessage)
                    }
                }
                return true
            }
        }
    }

    // MARK: - Private

    /// Shows the rejection banner for 2 seconds, resetting the timer on rapid successive drops.
    private func triggerRejectionHint(message: LocalizedStringResource) {
        // Cancel any in-flight hide task before restarting the timer so that rapid
        // consecutive drops each receive a full 2-second display window.
        rejectionTask?.cancel()
        rejectionMessage = message
        withAnimation(.spring(duration: 0.3)) {
            showRejectionHint = true
        }
        rejectionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showRejectionHint = false
            }
            rejectionMessage = nil
        }
    }

    private func determineRejectionMessage(
        unsupportedCount: Int,
        contentRejectedCount: Int
    ) -> LocalizedStringResource? {
        if unsupportedCount > 0, contentRejectedCount > 0 {
            return "label.drop_partial_rejection"
        }

        if unsupportedCount > 0 {
            return "label.unsupported_drop"
        }

        if contentRejectedCount > 0 {
            return contentRejectedMessage
        }

        return nil
    }
}

// MARK: - RejectionBanner

private struct RejectionBanner: View {
    let message: LocalizedStringResource

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
