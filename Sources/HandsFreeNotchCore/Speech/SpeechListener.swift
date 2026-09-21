//
//  SpeechListener.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import AVFoundation
import Foundation
import Speech

/// Streams the microphone into Apple's on-device recognizer and reports partial transcripts as
/// they form. Nothing leaves the Mac. The audio engine is prepared once at launch so a press of
/// the hotkey starts capturing in a few milliseconds.
public final class SpeechListener {
    /// Partial and final transcripts, on the main queue. `final` is true exactly once per listen.
    public var onTranscript: ((String, Bool) -> Void)?
    /// Microphone level 0...1 at about 20 Hz, on the main queue, for the notch bars.
    public var onLevel: ((Float) -> Void)?
    public var onError: ((Error) -> Void)?

    public private(set) var isListening = false
    public private(set) var onDevice = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastLevelAt: TimeInterval = 0
    private var finished = false

    public enum ListenError: LocalizedError {
        case notAuthorized, microphoneDenied, recognizerUnavailable

        public var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition is not allowed. Enable it in System Settings › Privacy & Security › Speech Recognition."
            case .microphoneDenied: return "Microphone access is not allowed. Enable it in System Settings › Privacy & Security › Microphone."
            case .recognizerUnavailable: return "Speech recognition is unavailable for this language right now."
            }
        }
    }

    public init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        onDevice = recognizer?.supportsOnDeviceRecognition ?? false
        engine.prepare()
    }

    public var authorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Asks for microphone and speech permission if they have not been decided yet.
    public func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { DispatchQueue.main.async { completion(false) }; return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    public func start() throws {
        guard !isListening else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw ListenError.notAuthorized }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw ListenError.microphoneDenied }
        guard let recognizer, recognizer.isAvailable else { throw ListenError.recognizerUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .search
        if #available(macOS 13, *) { request.addsPunctuation = false }
        onDevice = request.requiresOnDeviceRecognition
        self.request = request
        finished = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.report(level: buffer)
        }
        engine.prepare()
        try engine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async { [weak self] in
                    guard let self, !(isFinal && self.finished) else { return }
                    if isFinal { self.finished = true }
                    self.onTranscript?(text, isFinal)
                }
                if isFinal { self.teardown() }
            }
            if let error {
                // Ending audio with nothing said reports as an error; that is a normal empty result.
                let code = (error as NSError).code
                let benign = code == 1110 || code == 216 || code == 301
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    if benign { self.onTranscript?("", true) } else { self.onError?(error) }
                }
                self.teardown()
            }
        }
    }

    /// Stops capturing. The final transcript follows through `onTranscript` shortly after.
    public func stop() {
        guard isListening else { return }
        isListening = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
    }

    /// Stops and throws away whatever was heard.
    public func cancel() {
        finished = true
        stop()
        task?.cancel()
        teardown()
    }

    /// Delivers the last partial as final when the recognizer is slow to close out; the pipeline
    /// calls this after its own grace period.
    public func forceFinal(_ text: String) {
        guard !finished else { return }
        finished = true
        task?.cancel()
        teardown()
        onTranscript?(text, true)
    }

    private func teardown() {
        task = nil
        request = nil
        if isListening {
            isListening = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func report(level buffer: AVAudioPCMBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastLevelAt > 0.05, let data = buffer.floatChannelData?[0] else { return }
        lastLevelAt = now
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        var i = 0
        while i < n { sum += data[i] * data[i]; i += 4 }
        let rms = sqrt(sum / Float(n / 4))
        let db = 20 * log10(max(rms, 1e-7))
        let level = max(0, min(1, (db + 50) / 50))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
