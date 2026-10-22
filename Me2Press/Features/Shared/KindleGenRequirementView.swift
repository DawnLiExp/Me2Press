import SwiftUI

struct KindleGenRequirementView: View {
    let isRequired: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if isRequired, !settings.isKindleGenReady {
            HStack {
                if settings.kindleGenStatus == .checking {
                    ProgressView().controlSize(.small)
                }
                Text(settings.kindleGenStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "button.open_settings")) { openSettings() }
                    .controlSize(.small)
            }
            .padding(.top, 12)
        }
    }
}
