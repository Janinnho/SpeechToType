//
//  TextInputService.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import Cocoa
import Carbon.HIToolbox

class TextInputService {
    static let shared = TextInputService()

    private init() {}

    func insertText(_ text: String) {
        // Use CGEvent to simulate keyboard input
        // First, copy text to clipboard
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V to paste
        simulatePaste()

        // Restore previous clipboard content after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// Gets the currently selected text by simulating Cmd+C and reading from clipboard
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Clear clipboard
        pasteboard.clearContents()

        // Simulate Cmd+C to copy selected text
        simulateCopy()

        // Wait a bit for the copy to complete
        Thread.sleep(forTimeInterval: 0.1)

        // Get the copied text
        let selectedText = pasteboard.string(forType: .string)

        // Restore previous clipboard content
        pasteboard.clearContents()
        if let previous = previousContent {
            pasteboard.setString(previous, forType: .string)
        }

        // Return nil if nothing was copied or if it's the same as before
        if let text = selectedText, !text.isEmpty, text != previousContent {
            return text
        }

        return nil
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for Cmd+V
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up for Cmd+V
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func simulateCopy() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for Cmd+C
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up for Cmd+C
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // Alternative method using accessibility API
    func insertTextViaAccessibility(_ text: String) {
        // Get the focused element
        guard let systemWideElement = AXUIElementCreateSystemWide() as AXUIElement? else { return }

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let element = focusedElement {
            // Try to set the value directly
            AXUIElementSetAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, text as CFTypeRef)
        } else {
            // Fallback to paste method
            insertText(text)
        }
    }
}
