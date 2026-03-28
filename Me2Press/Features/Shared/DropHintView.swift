//
//  DropHintView.swift
//  Me2Press
//
//  Empty-state placeholder shown inside the drop zone when the queue is empty.
//  Highlights with accent color while a drag is hovered over the target.
//

import SwiftUI

struct DropHintView: View {
    let icon: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let isTargeted: Bool

    private var iconColor: Color {
        isTargeted ? Color.accentColor : Color(nsColor: .quaternaryLabelColor)
    }

    private var titleColor: Color {
        isTargeted ? Color.primary : Color(nsColor: .tertiaryLabelColor)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(titleColor)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)
            }

            Spacer()
        }
    }
}
