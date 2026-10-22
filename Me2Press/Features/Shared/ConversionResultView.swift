import SwiftUI

struct ConversionResultView: View {
    let progress: ConversionProgress
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: progress.isCompleted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(progress.isCompleted ? .green : .orange)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(String(localized: "result.summary \(progress.succeededCount) \(progress.failures.count)"))
                .foregroundStyle(.secondary)
            if progress.outcome == .cancelled {
                Text(String(localized: "result.unprocessed \(progress.unprocessedCount)"))
                    .foregroundStyle(.secondary)
            }
            if !progress.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(progress.failures) { failure in
                            Text(failure.message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            if !progress.outputURLs.isEmpty {
                Button(String(localized: "label.show_in_finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(progress.outputURLs)
                }
            }
            HStack {
                Button(String(localized: "result.back"), action: onDismiss)
                if !progress.failures.isEmpty {
                    Button(String(localized: "result.retry"), action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch progress.outcome {
        case .success: String(localized: "progress.done")
        case .failure: String(localized: "result.failed")
        case .cancelled: String(localized: "result.cancelled")
        case nil: ""
        }
    }
}
