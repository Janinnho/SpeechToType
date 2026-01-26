//
//  AudioRecorder.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import AVFoundation
import Combine
import CoreAudio

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case recordingFailed
    case noRecordingAvailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Mikrofonzugriff wurde verweigert. Bitte erlaube den Zugriff in den Systemeinstellungen."
        case .recordingFailed:
            return "Die Aufnahme konnte nicht gestartet werden."
        case .noRecordingAvailable:
            return "Keine Aufnahme verfügbar."
        }
    }
}

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedDeviceId: AudioDeviceID?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var levelTimer: Timer?
    private var lastLevelUpdateTime: Date?
    private let minLevelUpdateInterval: TimeInterval = 0.1 // Throttle to 10 updates/second max

    private override init() {
        super.init()
        refreshInputDevices()
    }

    /// Get all available audio input devices
    func refreshInputDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            availableInputDevices = []
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            availableInputDevices = []
            return
        }

        // Get default input device
        var defaultInputDevice: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultInputDevice
        )

        var inputDevices: [AudioInputDevice] = []

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputChannelsSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize)

            if status == noErr && inputChannelsSize > 0 {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize, bufferListPointer)

                if status == noErr {
                    let bufferList = bufferListPointer.pointee
                    var totalChannels: UInt32 = 0

                    withUnsafePointer(to: bufferList.mBuffers) { ptr in
                        for i in 0..<Int(bufferList.mNumberBuffers) {
                            let buffer = ptr.advanced(by: i).pointee
                            totalChannels += buffer.mNumberChannels
                        }
                    }

                    if totalChannels > 0 {
                        // Get device name
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyDeviceNameCFString,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )

                        var name: Unmanaged<CFString>?
                        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                        status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

                        if status == noErr, let cfName = name?.takeUnretainedValue() {
                            let deviceName = cfName as String
                            let isDefault = deviceID == defaultInputDevice
                            inputDevices.append(AudioInputDevice(id: deviceID, name: deviceName, isDefault: isDefault))
                        }
                    }
                }
            }
        }

        // Sort: default device first, then alphabetically
        inputDevices.sort { (a, b) in
            if a.isDefault { return true }
            if b.isDefault { return false }
            return a.name < b.name
        }

        DispatchQueue.main.async {
            self.availableInputDevices = inputDevices
            // Set selected device to default if not set
            if self.selectedDeviceId == nil, let defaultDevice = inputDevices.first(where: { $0.isDefault }) {
                self.selectedDeviceId = defaultDevice.id
            }
        }
    }

    /// Select a specific audio input device
    func selectInputDevice(_ deviceId: AudioDeviceID?) {
        selectedDeviceId = deviceId

        // If a device is selected, set it as the default input for our app
        if let deviceId = deviceId {
            setDefaultInputDevice(deviceId)
        }
    }

    /// Get the currently selected device
    var selectedDevice: AudioInputDevice? {
        guard let id = selectedDeviceId else {
            return availableInputDevices.first(where: { $0.isDefault })
        }
        return availableInputDevices.first(where: { $0.id == id })
    }

    private func setDefaultInputDevice(_ deviceId: AudioDeviceID) {
        var deviceId = deviceId
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceId
        )
    }
    
    var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    func startRecording() throws {
        guard hasPermission else {
            throw AudioRecorderError.permissionDenied
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(UUID().uuidString).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            audioLevel = 0.0

            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let newDuration = Date().timeIntervalSince(startTime)
                Task { @MainActor in
                    self.recordingDuration = newDuration
                }
            }

            // Start audio level metering
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
        } catch {
            throw AudioRecorderError.recordingFailed
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // Convert dB to linear scale (0.0 to 1.0)
        // -160 dB is silence, 0 dB is max
        let normalizedLevel = max(0, (level + 50) / 50)

        // Throttle UI updates to avoid layout conflicts
        let now = Date()
        if let lastUpdate = lastLevelUpdateTime, now.timeIntervalSince(lastUpdate) < minLevelUpdateInterval {
            return
        }
        lastLevelUpdateTime = now

        // Update on main thread safely
        Task { @MainActor in
            self.audioLevel = normalizedLevel
        }
    }
    
    func stopRecording() -> (URL, TimeInterval)? {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        guard let recorder = audioRecorder, recorder.isRecording else {
            return nil
        }

        let duration = recordingDuration
        recorder.stop()
        isRecording = false
        audioLevel = 0.0

        guard let url = recordingURL else {
            return nil
        }

        return (url, duration)
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingDuration = 0
        audioLevel = 0.0

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }
    
    func cleanupRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error.localizedDescription)")
        }
    }
}
