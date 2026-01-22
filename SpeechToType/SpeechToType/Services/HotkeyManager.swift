//
//  HotkeyManager.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import Carbon.HIToolbox
import Cocoa
import Combine
import SwiftUI

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var isListening = false
    @Published var isRecording = false
    @Published var isContinuousMode = false  // Double-tap toggle mode - stays recording until double-tap again
    @Published var statusMessage = String(localized: "ready")
    @Published var lastError: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var lastKeyPressTime: Date?
    private var lastKeyReleaseTime: Date?
    private let doubleTapInterval: TimeInterval = 0.3  // 300ms for double-tap detection

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onRewriteTriggered: (() -> Void)?

    private init() {}
    
    func startListening() {
        guard !isListening else { return }
        
        // Request accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            statusMessage = String(localized: "accessibilityRequired")
            return
        }
        
        setupEventTap()
    }
    
    func stopListening() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        isListening = false
        statusMessage = String(localized: "stopped")
    }
    
    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            statusMessage = String(localized: "eventTapFailed")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isListening = true
        statusMessage = String(localized: "readyHoldToRecord")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let settings = AppSettings.shared
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check for rewrite shortcut (if enabled)
        if settings.textRewriteEnabled && type == .keyDown {
            let rewriteShortcut = settings.rewriteShortcut
            let rewriteModifiers = CGEventFlags(rawValue: UInt64(rewriteShortcut.modifiers))

            // Check if the pressed key matches the rewrite shortcut
            if keyCode == rewriteShortcut.keyCode && matchesModifiers(flags, expected: rewriteModifiers) {
                DispatchQueue.main.async {
                    self.triggerRewrite()
                }
                return nil // Consume the event
            }
        }

        if type == .flagsChanged {
            // Check if Control key is used as hotkey
            if settings.useControlKey {
                let controlPressed = flags.contains(.maskControl)

                if controlPressed && !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async {
                        self.handleKeyPress()
                    }
                } else if !controlPressed && isKeyDown {
                    isKeyDown = false
                    DispatchQueue.main.async {
                        self.handleKeyRelease()
                    }
                }
            }

            return Unmanaged.passRetained(event)
        }

        // Handle regular key events if not using Control key
        if !settings.useControlKey {
            if keyCode == settings.hotkeyKeyCode {
                if type == .keyDown && !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async {
                        self.handleKeyPress()
                    }
                    return nil // Consume the event
                } else if type == .keyUp && isKeyDown {
                    isKeyDown = false
                    DispatchQueue.main.async {
                        self.handleKeyRelease()
                    }
                    return nil // Consume the event
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func matchesModifiers(_ actual: CGEventFlags, expected: CGEventFlags) -> Bool {
        // Check if the required modifiers are pressed
        let relevantMasks: [CGEventFlags] = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

        for mask in relevantMasks {
            let expectedHas = expected.contains(mask)
            let actualHas = actual.contains(mask)
            if expectedHas != actualHas {
                return false
            }
        }
        return true
    }

    private func triggerRewrite() {
        // Get selected text
        if let selectedText = TextInputService.shared.getSelectedText(),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TextRewriteWindowController.shared.show(with: selectedText)
            onRewriteTriggered?()
        }
    }

    private func handleKeyPress() {
        let now = Date()

        // Check for double-tap (based on release times for toggle mode)
        if let lastRelease = lastKeyReleaseTime,
           now.timeIntervalSince(lastRelease) < doubleTapInterval {
            // Double-tap detected!
            if isContinuousMode && isRecording {
                // Already in continuous mode - stop recording
                isContinuousMode = false
                stopRecording()
                lastKeyReleaseTime = nil
                lastKeyPressTime = nil
                return
            } else if !isRecording {
                // Start continuous recording mode
                isContinuousMode = true
                startRecording()
                lastKeyReleaseTime = nil
                lastKeyPressTime = nil
                return
            }
        }

        // Normal single tap - start recording if not already
        lastKeyPressTime = now
        if !isRecording {
            startRecording()
        }
    }

    private func handleKeyRelease() {
        let now = Date()
        lastKeyReleaseTime = now

        if isContinuousMode {
            // In continuous mode, key release does NOT stop recording
            // Recording continues until double-tap
            return
        } else if isRecording {
            // Normal hold-to-record mode - stop on release
            stopRecording()
        }
    }

    // Public method to start continuous recording from menu
    func startContinuousRecording() {
        guard !isRecording else { return }
        isContinuousMode = true
        startRecording()
    }

    // Public method to stop recording from menu
    func stopCurrentRecording() {
        guard isRecording else { return }
        isContinuousMode = false
        stopRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        statusMessage = isContinuousMode ? String(localized: "recordingContinuous") : String(localized: "recording")

        // Show overlay window
        RecordingOverlayWindowController.shared.show()

        onRecordingStarted?()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isContinuousMode = false
        statusMessage = String(localized: "processing")

        // Hide overlay window
        RecordingOverlayWindowController.shared.hide()

        onRecordingStopped?()
    }
    
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
