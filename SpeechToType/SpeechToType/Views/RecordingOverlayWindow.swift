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
    private let bottomMargin: CGFloat = 20

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

    /// Recent input levels, newest last, for the waveform
    @State private var levels: [Float] = Array(repeating: 0, count: 26)

    var body: some View {
        Group {
            switch controller.mode {
            case .recording:
                compact {
                    PulsingDot()
                    WaveformBars(levels: levels)
                        .frame(height: 24)
                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .frame(minWidth: 44, alignment: .leading)
                }
            case .processing:
                compact {
                    ProgressView()
                        .controlSize(.small)
                    Text("processing")
                        .font(.body.weight(.medium))
                }
            case .live:
                liveContent
            }
        }
        // Room for the glass edge and shadow inside the borderless window
        .padding(8)
        .onReceive(audioRecorder.$audioLevel) { level in
            levels.append(level)
            levels.removeFirst(levels.count - 26)
        }
    }

    // MARK: - Layouts

    private func compact<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("liveTranscription")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(controller.liveText.isEmpty
                 ? String(localized: "overlayListening")
                 : controller.liveText)
                .font(.system(size: 15))
                .foregroundStyle(controller.liveText.isEmpty ? .secondary : .primary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: width, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Bars that follow the microphone level, oldest on the left
struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red.gradient)
                    .frame(width: 3, height: max(3, CGFloat(min(levels[index] * 1.4, 1)) * 24))
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .shadow(color: .red.opacity(0.6), radius: isPulsing ? 5 : 1)
            .opacity(isPulsing ? 0.5 : 1.0)
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
