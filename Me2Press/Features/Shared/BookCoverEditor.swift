import SwiftUI

struct BookCoverEditor: View {
    let sourceURL: URL
    let hint: LocalizedStringResource
    @Binding var coverURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(sourceURL.lastPathComponent)
                .font(.headline)
                .lineLimit(2)
                .help(sourceURL.path)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            CoverDropZone(coverURL: $coverURL)
            Button(String(localized: "cover.done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
        .onExitCommand { dismiss() }
    }
}
