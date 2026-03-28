//
//  FileQueueView.swift
//  Me2Press
//
//  Generic queue container used by all three conversion tabs.
//  Composes DropHintView (empty state) and FileRowView (item rows)
//  inside a dashed-border drop target.
//  Shows a rejection banner when unsupported file types are dropped,
//  or when valid-typed items produce no additions (e.g. empty comic folders).
//

import SwiftUI
import UniformTypeIdentifiers

struct FileQueueView: View {
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

    // MARK: Actions

    let onClearAll: () -> Void
    let onRemove: (URL) -> Void
    let onReveal: (URL) -> Void
    /// Validates whether a dropped URL is acceptable for this queue.
    let accepts: (URL) -> Bool
    /// Called with only the accepted URLs after a successful drop.
    /// Returns the number of items actually added to the queue.
    let onDropped: ([URL]) -> Int
    /// Optional reorder handler. When provided, rows become drag-reorderable.
    var onMove: ((IndexSet, Int) -> Void)?

    // MARK: Rejection state

    @State private var showRejectionHint = false
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
                        .help(String(localized: tooltip))
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

                    Text("\(items.count) \(String(localized: countLabel))")
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

                if showRejectionHint {
                    RejectionBanner()
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
                    let rejectedByType = resolved.count - valid.count

                    // Distinguish two rejection cases:
                    // • Type mismatch: none of the dropped items pass the accepts() filter.
                    // • Content rejection: items pass the type filter but onDropped() adds nothing
                    //   (e.g. a valid-extension folder that contains no usable image files).
                    if !valid.isEmpty {
                        let addedCount = withAnimation { onDropped(valid) }
                        if addedCount == 0 {
                            triggerRejectionHint()
                        }
                    } else if rejectedByType > 0 {
                        triggerRejectionHint()
                    }
                }
                return true
            }
        }
    }

    // MARK: - Private

    /// Shows the rejection banner for 2 seconds, resetting the timer on rapid successive drops.
    private func triggerRejectionHint() {
        // Cancel any in-flight hide task before restarting the timer so that rapid
        // consecutive drops each receive a full 2-second display window.
        rejectionTask?.cancel()
        withAnimation(.spring(duration: 0.3)) {
            showRejectionHint = true
        }
        rejectionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showRejectionHint = false
            }
        }
    }
}

// MARK: - RejectionBanner

private struct RejectionBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            Text(String(localized: "label.unsupported_drop"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
