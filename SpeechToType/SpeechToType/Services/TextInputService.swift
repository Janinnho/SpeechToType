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

    /// Stores the previously active application (before our app took focus)
    private var previousApp: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication?

    private init() {
        // Observe app activation changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appWillDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Initialize with current frontmost app if it's not us
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
            lastActiveApp = frontmost
        }
    }

    @objc private func appWillDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // When another app (not us) is deactivating, remember it
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = app
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // When our app becomes active, save the last active app as the previous app
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            if let last = lastActiveApp {
                previousApp = last
            }
        }
    }

    /// Gets the previously active application
    func getPreviousApp() -> NSRunningApplication? {
        return previousApp
    }

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
        // First try to get selected text via Accessibility API (works even when our app has focus)
        if let accessibilityText = getSelectedTextViaAccessibility() {
            return accessibilityText
        }

        // Fallback to clipboard method
        return getSelectedTextViaClipboard()
    }

    /// Gets selected text using the Accessibility API from the previously active app
    private func getSelectedTextViaAccessibility() -> String? {
        // Try to get selected text from the previously active app
        if let prevApp = previousApp,
           let text = getSelectedTextFromApp(prevApp) {
            return text
        }

        // Fallback: try current focused app
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let appElement = focusedApp else {
            return nil
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }

        var selectedText: AnyObject?
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
           let text = selectedText as? String,
           !text.isEmpty {
            return text
        }

        return nil
    }

    /// Gets selected text from a specific application using Accessibility API
    private func getSelectedTextFromApp(_ app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element within that application
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }

        // Try to get the selected text
        var selectedText: AnyObject?
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
           let text = selectedText as? String,
           !text.isEmpty {
            return text
        }

        return nil
    }

    /// Gets selected text using clipboard simulation (Cmd+C)
    private func getSelectedTextViaClipboard() -> String? {
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
