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

    @State private var isHovered = false

    private var removeButtonColor: Color {
        isHovered ? tint.opacity(0.6) : Color(nsColor: .tertiaryLabelColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(isHovered ? 1.0 : 0.8))
                .font(.system(size: 14))
                .animation(.easeInOut(duration: 0.15), value: isHovered)

            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(removeButtonColor)
                    .font(.system(size: 14))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .buttonStyle(.plain)
        }
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
