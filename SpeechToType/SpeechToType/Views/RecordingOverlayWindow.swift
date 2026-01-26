//
//  RecordingOverlayWindow.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import SwiftUI
import AppKit
import Combine

enum OverlayMode {
    case recording
    case processing
}

@MainActor
class RecordingOverlayWindowController: NSObject, ObservableObject {
    static let shared = RecordingOverlayWindowController()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    @Published var isVisible = false
    @Published var mode: OverlayMode = .recording

    private override init() {
        super.init()
    }

    func show(mode: OverlayMode = .recording) {
        self.mode = mode

        guard overlayWindow == nil else {
            overlayWindow?.orderFront(nil)
            isVisible = true
            return
        }

        let contentView = RecordingOverlayView(controller: self)
        hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true
        window.hasShadow = true

        // Position in bottom-right corner of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let xPos = screenFrame.maxX - windowFrame.width - 20
            let yPos = screenFrame.minY + 20
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }

        overlayWindow = window
        window.orderFront(nil)
        isVisible = true
    }

    func hide() {
        overlayWindow?.orderOut(nil)
        isVisible = false
    }

    func showProcessing() {
        show(mode: .processing)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var controller: RecordingOverlayWindowController
    @ObservedObject var audioRecorder = AudioRecorder.shared

    var body: some View {
        HStack(spacing: 12) {
            if controller.mode == .recording {
                // Recording indicator - simple pulsing dot
                PulsingDot()

                // Duration
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 50, alignment: .leading)
            } else {
                // Processing indicator - spinning circle
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)

                Text("processing")
                    .font(.system(.body))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .fixedSize()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .opacity(isPulsing ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

#Preview {
    RecordingOverlayView(controller: RecordingOverlayWindowController.shared)
        .padding()
        .background(Color.gray)
}
