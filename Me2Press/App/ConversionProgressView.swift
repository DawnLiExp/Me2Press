//
//  ConversionProgressView.swift
//  Me2Press
//
//  Adapts its display to the active execution mode:
//  Sequential (isConcurrent = false): fine-grained ring, live step label, current filename.
//  Concurrent (isConcurrent = true): whole-file ring steps, fixed "Processing…" label, no filename.
//

import SwiftUI

struct ConversionProgressView: View {
    let progress: ConversionProgress
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Ring + center label ───────────────────────────────────────
            ZStack {
                ProgressRing(
                    progress: progress.value,
                    isCompleted: progress.isCompleted
                )
                centerLabel
            }

            Spacer().frame(height: 28)

            // ── Labels area — fixed height prevents layout jumps on text change ──
            VStack(spacing: 0) {
                Text(stepText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.2), value: progress.step)

                if showsFileDetails {
                    Spacer().frame(height: 10)
                }

                if progress.totalFiles > 1 {
                    Text(fileCountText)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                if !progress.isConcurrent,
                   !progress.currentFileName.isEmpty,
                   !progress.isCompleted
                {
                    Text(progress.currentFileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                }

                if !progress.isConcurrent,
                   !progress.volumeLabel.isEmpty,
                   !progress.isCompleted
                {
                    Text(progress.volumeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 3)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: progress.volumeLabel)
                }
            }
            .frame(height: 96, alignment: .top)

            Spacer()

            // ── Stop button — hidden on completion ────────────────────────
            stopArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Computed helpers

    private var stepText: String {
        if progress.isCompleted {
            return String(localized: "progress.done")
        }
        if progress.isConcurrent {
            return String(localized: "progress.processing")
        }
        return progress.step
    }

    private var fileCountText: String {
        let idx = progress.isConcurrent ? progress.completedCount : progress.fileIndex
        return String(localized: "progress.file \(idx) \(progress.totalFiles)")
    }

    private var showsFileDetails: Bool {
        if progress.totalFiles > 1 { return true }
        if !progress.isConcurrent,
           !progress.currentFileName.isEmpty,
           !progress.isCompleted { return true }
        return false
    }

    // MARK: - Sub-views

    private var centerLabel: some View {
        Group {
            if progress.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Text("\(Int(progress.value * 100))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: progress.isCompleted)
    }

    private var stopArea: some View {
        Group {
            if !progress.isCompleted {
                ConvertStopButton(
                    isConverting: true,
                    isDisabled: false,
                    action: onStop
                )
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 40)
            }
        }
        .padding(.bottom, 24)
        .animation(.easeInOut(duration: 0.2), value: progress.isCompleted)
    }
}
