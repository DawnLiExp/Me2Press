//
//  WindowDragArea.swift
//  Me2Press
//
//  AppKit bridge: enables window drag via mouseDownCanMoveWindow.
//

import AppKit
import SwiftUI

// MARK: - WindowDragArea

/// Transparent NSViewRepresentable that makes its covered area drag the window
/// via mouseDownCanMoveWindow. Used in the sidebar and custom title-bar areas.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        DraggableNSView()
    }

    func updateNSView(_ nsView: DraggableNSView, context: Context) {}

    final class DraggableNSView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // IMPORTANT: window is only available after the view enters the hierarchy;
            // isMovableByWindowBackground must be set here rather than in init().
            window?.isMovableByWindowBackground = true
        }

        override var mouseDownCanMoveWindow: Bool {
            true
        }
    }
}
