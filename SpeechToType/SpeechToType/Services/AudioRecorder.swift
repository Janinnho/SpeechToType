//
//  AudioRecorder.swift
//  SpeechToType
//
//  Created on 18.01.26.
//

import Foundation
import AVFoundation
import Combine

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

class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var levelTimer: Timer?

    private override init() {
        super.init()
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
                self.recordingDuration = Date().timeIntervalSince(startTime)
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
        audioLevel = normalizedLevel

        // Update overlay window
        RecordingOverlayWindowController.shared.updateAudioLevel(normalizedLevel)
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
