import SwiftUI

struct ConversionProgressView: View {
    let progress: ConversionProgress
    var isStopping = false
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                ProgressRing(progress: progress.value)
                Text(verbatim: "\(Int(progress.value * 100))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "progress.accessibility"))
            .accessibilityValue(progress.value.formatted(.percent.precision(.fractionLength(0))))

            VStack(spacing: 8) {
                Text(stepText).font(.subheadline).foregroundStyle(.secondary)
                if progress.totalFiles > 1 {
                    Text(fileCountText).font(.caption).foregroundStyle(.secondary)
                }
                if !progress.isConcurrent, !progress.currentFileName.isEmpty {
                    Text(progress.currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(progress.currentFileName)
                }
                if !progress.isConcurrent, !progress.volumeLabel.isEmpty {
                    Text(progress.volumeLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .frame(minHeight: 124, alignment: .top)
            Spacer()
            ConvertStopButton(isConverting: true, isDisabled: isStopping, isStopping: isStopping, action: onStop)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var stepText: String {
        if isStopping { return String(localized: "progress.stopping") }
        return progress.isConcurrent ? String(localized: "progress.processing") : progress.step
    }

    private var fileCountText: String {
        if progress.isConcurrent {
            return String(localized: "progress.processed \(progress.completedCount) \(progress.totalFiles)")
        }
        return String(localized: "progress.file \(progress.fileIndex) \(progress.totalFiles)")
    }
}
