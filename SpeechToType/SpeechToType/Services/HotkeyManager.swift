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
    @Published var statusMessage = String(localized: "ready")
    @Published var lastError: String?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    
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
        
        if type == .flagsChanged {
            let flags = event.flags
            
            // Check if Control key is used as hotkey
            if settings.useControlKey {
                let controlPressed = flags.contains(.maskControl)
                
                if controlPressed && !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async {
                        self.startRecording()
                    }
                } else if !controlPressed && isKeyDown {
                    isKeyDown = false
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        // Handle regular key events if not using Control key
        if !settings.useControlKey {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            if keyCode == Int64(settings.hotkeyKeyCode) {
                if type == .keyDown && !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async {
                        self.startRecording()
                    }
                    return nil // Consume the event
                } else if type == .keyUp && isKeyDown {
                    isKeyDown = false
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                    return nil // Consume the event
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        statusMessage = String(localized: "recording")
        onRecordingStarted?()
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusMessage = String(localized: "processing")
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
