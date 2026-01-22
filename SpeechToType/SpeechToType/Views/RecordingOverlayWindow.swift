//
//  RecordingOverlayWindow.swift
//  SpeechToType
//
//  Created on 22.01.26.
//

import SwiftUI
import AppKit
import Combine
import QuartzCore

@MainActor
class RecordingOverlayWindowController: NSObject, ObservableObject {
    static let shared = RecordingOverlayWindowController()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    @Published var audioLevel: Float = 0.0
    @Published var isVisible = false
    private var isUpdatingLevel = false

    private override init() {
        super.init()
    }

    func show() {
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

    func updateAudioLevel(_ level: Float) {
        // Prevent re-entrant updates that could cause layout conflicts
        guard !isUpdatingLevel else { return }
        isUpdatingLevel = true

        // Use CATransaction to batch the update and prevent layout thrashing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.audioLevel = level
        CATransaction.commit()

        isUpdatingLevel = false
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var controller: RecordingOverlayWindowController
    @ObservedObject var audioRecorder = AudioRecorder.shared
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1 + animationPhase * 0.3)
                        .opacity(1 - animationPhase)
                )

            // Sound wave visualization
            SoundWaveView(audioLevel: controller.audioLevel)
                .frame(width: 60, height: 30)

            // Duration
            Text(formatDuration(audioRecorder.recordingDuration))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SoundWaveView: View {
    var audioLevel: Float
    @State private var phases: [CGFloat] = Array(repeating: 0, count: 5)
    @State private var smoothedLevel: Float = 0.3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                SoundWaveBar(
                    baseHeight: barHeight(for: index),
                    phase: phases[index]
                )
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Smooth out level changes to reduce layout updates
            withAnimation(.linear(duration: 0.1)) {
                smoothedLevel = max(0.3, min(1.0, newLevel * 3 + 0.3))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeights: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]
        return baseHeights[index] * CGFloat(smoothedLevel)
    }

    private func startAnimations() {
        for i in 0..<5 {
            let delay = Double(i) * 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.4 + Double(i) * 0.05).repeatForever(autoreverses: true)) {
                    phases[i] = 1
                }
            }
        }
    }
}

struct SoundWaveBar: View {
    var baseHeight: CGFloat
    var phase: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 4, height: max(4, 30 * baseHeight * (0.5 + phase * 0.5)))
    }
}

#Preview {
    RecordingOverlayView(controller: RecordingOverlayWindowController.shared)
        .padding()
        .background(Color.gray)
}
