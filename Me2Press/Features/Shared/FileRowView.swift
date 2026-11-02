//
//  FileRowView.swift
//  Me2Press
//
//  A single row in the file/folder queue: icon, filename, remove button,
//  and a context menu with "Show in Finder" and "Remove" actions.
//

import AppKit
import SwiftUI

struct FileRowView: View {
    let url: URL
    let icon: String
    let tint: Color
    let onRemove: () -> Void
    let onReveal: () -> Void
    var coverURL: URL?
    var onChooseCover: (() -> Void)?
    var onRemoveCover: (() -> Void)?
    var defaultCoverHint: LocalizedStringResource?

    @State private var isHovered = false
    @State private var coverImage: NSImage?

    private var removeButtonColor: Color {
        isHovered ? tint.opacity(0.6) : Color(nsColor: .tertiaryLabelColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable().scaledToFit()
                    .frame(width: 32, height: 44)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(tint.opacity(isHovered ? 1.0 : 0.8))
                    .font(.system(size: 14))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if coverURL == nil, let defaultCoverHint {
                    Text(defaultCoverHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .help(url.path)

            Spacer()

            if let onChooseCover {
                Menu(String(localized: "cover.menu")) {
                    if coverURL == nil {
                        Button(String(localized: "cover.choose"), action: onChooseCover)
                    } else {
                        Button(String(localized: "cover.replace"), action: onChooseCover)
                        if let onRemoveCover {
                            Button(String(localized: "cover.remove"), action: onRemoveCover)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel(String(localized: "cover.for \(url.lastPathComponent)"))
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(removeButtonColor)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "button.remove"))
            .accessibilityLabel(String(localized: "queue.remove_item \(url.lastPathComponent)"))
        }
        .accessibilityElement(children: .contain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered
                    ? tint.opacity(0.08)
                    : Color.primary.opacity(0.03))
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isHovered ? tint.opacity(0.18) : Color.clear,
                    lineWidth: 0.5
                )
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .padding(.horizontal, 12)
        .onHover { isHovered = $0 }
        .task(id: coverURL) { coverImage = coverURL.flatMap { NSImage(contentsOf: $0) } }
        .contextMenu {
            Button(action: onReveal) {
                Label(String(localized: "label.show_in_finder"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label(String(localized: "button.remove"), systemImage: "trash")
            }
        }
    }
}
