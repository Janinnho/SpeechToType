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

    // State tracking for direct dictation (hold key)
    private var isDirectDictationKeyDown = false

    // State tracking for continuous recording (double-tap)
    private var lastContinuousTapTime: Date?
    private var continuousTapCount = 0
    private let doubleTapInterval: TimeInterval = 0.3  // 300ms for double-tap detection

    // State tracking for modifier keys
    private var isRightOptionDown = false
    private var isRightControlDown = false

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

        // Handle text rewrite shortcut (key combination)
        if settings.textRewriteEnabled {
            let rewriteShortcut = settings.rewriteShortcut
            if let consumed = handleRewriteShortcut(type: type, keyCode: keyCode, flags: flags, shortcut: rewriteShortcut) {
                return consumed
            }
        }

        // Handle direct dictation shortcut (hold key)
        let directShortcut = settings.directDictationShortcut
        if let consumed = handleDirectDictationShortcut(type: type, keyCode: keyCode, flags: flags, shortcut: directShortcut) {
            return consumed
        }

        // Handle continuous recording shortcut (double-tap)
        let continuousShortcut = settings.continuousRecordingShortcut
        if let consumed = handleContinuousRecordingShortcut(type: type, keyCode: keyCode, flags: flags, shortcut: continuousShortcut) {
            return consumed
        }

        // Legacy support: Check if Control key is used as hotkey (backward compatibility)
        if settings.useControlKey && type == .flagsChanged {
            let controlPressed = flags.contains(.maskControl)

            if controlPressed && !isDirectDictationKeyDown {
                isDirectDictationKeyDown = true
                DispatchQueue.main.async {
                    self.handleDirectDictationPress()
                }
            } else if !controlPressed && isDirectDictationKeyDown {
                isDirectDictationKeyDown = false
                DispatchQueue.main.async {
                    self.handleDirectDictationRelease()
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Rewrite Shortcut Handler

    private func handleRewriteShortcut(type: CGEventType, keyCode: Int, flags: CGEventFlags, shortcut: ShortcutConfig) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return nil }

        let expectedModifiers = CGEventFlags(rawValue: UInt64(shortcut.modifiers))

        // Check if the pressed key matches the rewrite shortcut
        if keyCode == shortcut.keyCode && matchesModifiers(flags, expected: expectedModifiers) {
            DispatchQueue.main.async {
                self.triggerRewrite()
            }
            return nil // Consume the event
        }

        return nil
    }

    // MARK: - Direct Dictation Shortcut Handler (Hold Key)

    private func handleDirectDictationShortcut(type: CGEventType, keyCode: Int, flags: CGEventFlags, shortcut: ShortcutConfig) -> Unmanaged<CGEvent>? {
        // Handle modifier-only shortcuts (like Right Option alone)
        if shortcut.isModifierOnly && type == .flagsChanged {
            let isRightOptionKey = shortcut.keyCode == kVK_RightOption
            let isOptionKey = shortcut.keyCode == kVK_Option

            if isRightOptionKey || isOptionKey {
                // Check if Right Option key state changed
                let rightOptionPressed = keyCode == kVK_RightOption
                let optionFlagActive = flags.contains(.maskAlternate)

                if rightOptionPressed && optionFlagActive && !isDirectDictationKeyDown {
                    // Right Option pressed - only trigger if no other modifiers
                    if !flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskShift) {
                        isDirectDictationKeyDown = true
                        isRightOptionDown = true
                        DispatchQueue.main.async {
                            self.handleDirectDictationPress()
                        }
                        return nil // Consume the event
                    }
                } else if !optionFlagActive && isDirectDictationKeyDown && isRightOptionDown {
                    // Right Option released
                    isDirectDictationKeyDown = false
                    isRightOptionDown = false
                    DispatchQueue.main.async {
                        self.handleDirectDictationRelease()
                    }
                    return nil // Consume the event
                }
            }

            // Handle Control key as modifier-only
            let isRightControlKey = shortcut.keyCode == kVK_RightControl
            let isControlKey = shortcut.keyCode == kVK_Control

            if isRightControlKey || isControlKey {
                let controlPressed = flags.contains(.maskControl)

                if controlPressed && !isDirectDictationKeyDown {
                    isDirectDictationKeyDown = true
                    isRightControlDown = true
                    DispatchQueue.main.async {
                        self.handleDirectDictationPress()
                    }
                    return nil
                } else if !controlPressed && isDirectDictationKeyDown && isRightControlDown {
                    isDirectDictationKeyDown = false
                    isRightControlDown = false
                    DispatchQueue.main.async {
                        self.handleDirectDictationRelease()
                    }
                    return nil
                }
            }
        }

        // Handle regular key shortcuts
        if !shortcut.isModifierOnly {
            let expectedModifiers = CGEventFlags(rawValue: UInt64(shortcut.modifiers))

            if type == .keyDown && keyCode == shortcut.keyCode && matchesModifiers(flags, expected: expectedModifiers) {
                if !isDirectDictationKeyDown {
                    isDirectDictationKeyDown = true
                    DispatchQueue.main.async {
                        self.handleDirectDictationPress()
                    }
                    return nil // Consume
                }
            } else if type == .keyUp && keyCode == shortcut.keyCode && isDirectDictationKeyDown {
                isDirectDictationKeyDown = false
                DispatchQueue.main.async {
                    self.handleDirectDictationRelease()
                }
                return nil // Consume
            }
        }

        return nil
    }

    // MARK: - Continuous Recording Shortcut Handler (Double-Tap)

    private func handleContinuousRecordingShortcut(type: CGEventType, keyCode: Int, flags: CGEventFlags, shortcut: ShortcutConfig) -> Unmanaged<CGEvent>? {
        // For modifier-only shortcuts (double-tap Right Option)
        if shortcut.isModifierOnly && type == .flagsChanged {
            let isRightOptionKey = shortcut.keyCode == kVK_RightOption
            let isOptionKey = shortcut.keyCode == kVK_Option

            if isRightOptionKey || isOptionKey {
                // Detect key release (transition from pressed to not pressed)
                if keyCode == kVK_RightOption && !flags.contains(.maskAlternate) {
                    checkDoubleTapForContinuous()
                }
            }
        }

        // For key combination shortcuts (like Cmd+D double-tap)
        if !shortcut.isModifierOnly && type == .keyUp {
            let expectedModifiers = CGEventFlags(rawValue: UInt64(shortcut.modifiers))
            if keyCode == shortcut.keyCode && matchesModifiers(flags, expected: expectedModifiers) {
                checkDoubleTapForContinuous()
            }
        }

        return nil
    }

    private func checkDoubleTapForContinuous() {
        let now = Date()

        if let lastTap = lastContinuousTapTime, now.timeIntervalSince(lastTap) < doubleTapInterval {
            // Double-tap detected!
            continuousTapCount = 0
            lastContinuousTapTime = nil

            DispatchQueue.main.async {
                if self.isContinuousMode && self.isRecording {
                    // Already in continuous mode - stop recording
                    self.isContinuousMode = false
                    self.stopRecording()
                } else if !self.isRecording {
                    // Start continuous recording mode
                    self.isContinuousMode = true
                    self.startRecording()
                }
            }
        } else {
            // First tap, wait for potential second tap
            lastContinuousTapTime = now
            continuousTapCount = 1
        }
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
        // Get selected text with retry mechanism for better detection
        if let selectedText = TextInputService.shared.getSelectedTextWithRetry(maxAttempts: 3, delayBetweenAttempts: 0.05),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TextRewriteWindowController.shared.show(with: selectedText)
            onRewriteTriggered?()
        } else {
            // Show alert if no text was found
            TextRewriteWindowController.shared.showNoTextSelectedAlert()
        }
    }

    // MARK: - Direct Dictation Handlers (Hold to Record)

    private func handleDirectDictationPress() {
        // Don't start if already in continuous mode
        if isContinuousMode { return }

        if !isRecording {
            startRecording()
        }
    }

    private func handleDirectDictationRelease() {
        // Don't stop if in continuous mode
        if isContinuousMode { return }

        if isRecording {
            stopRecording()
        }
    }

    // Legacy handlers for backward compatibility
    private func handleKeyPress() {
        handleDirectDictationPress()
    }

    private func handleKeyRelease() {
        handleDirectDictationRelease()
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

        // Show overlay window - must be done on MainActor
        Task { @MainActor in
            RecordingOverlayWindowController.shared.show()
        }

        onRecordingStarted?()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isContinuousMode = false
        statusMessage = String(localized: "processing")

        // Hide overlay window - must be done on MainActor
        Task { @MainActor in
            RecordingOverlayWindowController.shared.hide()
        }

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
