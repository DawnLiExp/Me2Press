import SwiftUI

struct ConvertStopButton: View {
    let isConverting: Bool
    let isDisabled: Bool
    var isStopping = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isConverting ? "stop.fill" : "arrow.triangle.2.circlepath")
                .font(.headline)
                .frame(minWidth: 110, minHeight: 24)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isConverting ? .red : .accentColor)
        .disabled(isDisabled)
    }

    private var title: String {
        if isStopping { return String(localized: "progress.stopping") }
        return String(localized: isConverting ? "button.stop" : "button.convert")
    }
}
