//
//  ProgressRing.swift
//  Me2Press
//
//  Double-layer arc progress ring: track + gradient progress arc.
//  Animates smoothly on progress changes; switches to green on completion.
//

import SwiftUI

struct ProgressRing: View {
    let progress: Double // 0.0 – 1.0
    var isCompleted: Bool = false
    var lineWidth: CGFloat = 12
    var size: CGFloat = 164

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            // ── Background track ──────────────────────────────────────────
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            // ── Progress arc ──────────────────────────────────────────────
            Circle()
                .trim(from: 0, to: isCompleted ? 1.0 : clamped)
                .stroke(
                    LinearGradient(
                        colors: isCompleted
                            ? [Color.green.opacity(0.65), Color.green]
                            : [Color.accentColor.opacity(0.5), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Two separate animations so each value gets its own spring tuning:
                // progress arc uses a slower, softer spring; completion fill uses a tighter one.
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82),
                    value: clamped
                )
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.9),
                    value: isCompleted
                )
        }
        .frame(width: size, height: size)
    }
}
