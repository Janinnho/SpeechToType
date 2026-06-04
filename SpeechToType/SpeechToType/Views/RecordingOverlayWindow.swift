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
    case live
}

@MainActor
class RecordingOverlayWindowController: NSObject, ObservableObject {
    static let shared = RecordingOverlayWindowController()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    @Published var isVisible = false
    @Published var mode: OverlayMode = .recording
    /// Live (interim) transcription preview shown while speaking in real-time mode.
    @Published var liveText: String = ""

    /// Distance from the bottom edge of the screen.
    private let bottomMargin: CGFloat = 28

    private override init() {
        super.init()
    }

    /// Fixed width of the overlay, derived from the screen width (clamped).
    private var overlayWidth: CGFloat {
        let screenWidth = (NSScreen.main?.visibleFrame.width ?? 1280)
        return min(max(screenWidth * 0.42, 360), 620)
    }

    func show(mode: OverlayMode = .recording) {
        self.mode = mode

        if overlayWindow == nil {
            let contentView = RecordingOverlayView(controller: self, width: overlayWidth)
            let hosting = NSHostingView(rootView: contentView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: overlayWidth, height: 80),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.hasShadow = true

            overlayWindow = window
            hostingView = hosting
        }

        resizeAndReposition()
        overlayWindow?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        overlayWindow?.orderOut(nil)
        isVisible = false
    }

    func showProcessing() {
        show(mode: .processing)
    }

    func showLive() {
        liveText = ""
        show(mode: .live)
    }

    func updateLive(_ text: String) {
        liveText = text
        // Let SwiftUI apply the @Published change, then resize the window to fit.
        DispatchQueue.main.async { [weak self] in
            self?.resizeAndReposition()
        }
    }

    /// Resizes the window to the SwiftUI content's fitting size and keeps it anchored at
    /// the bottom-center of the screen, so it grows upward as more text arrives.
    private func resizeAndReposition() {
        guard let window = overlayWindow, let hostingView = hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()

        let fitting = hostingView.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }

        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let width = fitting.width
        // Cap the height so the box never exceeds the screen; bottom-anchored growth keeps
        // the newest text visible at the bottom.
        let height = min(fitting.height, visible.height - bottomMargin * 2)
        let x = visible.midX - width / 2
        let y = visible.minY + bottomMargin

        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var controller: RecordingOverlayWindowController
    @ObservedObject var audioRecorder = AudioRecorder.shared
    let width: CGFloat

    var body: some View {
        Group {
            switch controller.mode {
            case .recording:
                compact {
                    PulsingDot()
                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 50, alignment: .leading)
                }
            case .processing:
                compact {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                    Text("processing")
                        .foregroundStyle(.white)
                }
            case .live:
                liveContent
            }
        }
    }

    // MARK: - Layouts

    private func compact<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background)
        .fixedSize()
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("liveTranscription")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
            }

            Text(controller.liveText.isEmpty
                 ? String(localized: "overlayListening")
                 : controller.liveText)
                .font(.system(size: 15))
                .foregroundStyle(controller.liveText.isEmpty ? .white.opacity(0.5) : .white)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: width, alignment: .leading)
        .background(background)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
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
            .frame(width: 10, height: 10)
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

#Preview {
    RecordingOverlayView(controller: RecordingOverlayWindowController.shared, width: 480)
        .padding()
        .background(Color.gray)
}
