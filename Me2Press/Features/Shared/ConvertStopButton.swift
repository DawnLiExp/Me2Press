//
//  ConvertStopButton.swift
//  Me2Press
//
//  Shared Convert / Stop toggle button used across all conversion tabs.
//

import SwiftUI

/// Dual-state Convert / Stop button.
/// - Idle: blue "Convert", can be disabled via `isDisabled`.
/// - Converting: red "Stop", always tappable.
struct ConvertStopButton: View {
    let isConverting: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isConverting {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                }

                Text(isConverting
                    ? String(localized: "button.stop")
                    : String(localized: "button.convert"))
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(width: 130, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isConverting ? Color.red.opacity(0.85) : Color.accentColor)
            )
            .foregroundStyle(.white)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // States are mutually exclusive — Stop is only shown during conversion, Convert
        // only when idle — so rapid double-tap cannot trigger both actions simultaneously.
        .animation(.easeInOut(duration: 0.15), value: isConverting)
    }
}
