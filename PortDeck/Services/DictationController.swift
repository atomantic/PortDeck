import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class DictationController {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var initialText = ""
    private var hasInputTap = false

    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    func toggle(initialText: String) async {
        if isRecording { stop() }
        else { await start(initialText: initialText) }
    }

    func start(initialText: String) async {
        stop()
        errorMessage = nil
        self.initialText = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = self.initialText

        guard await requestSpeechAuthorization() else {
            errorMessage = "Speech Recognition permission is required for dictation."
            return
        }
        guard await requestMicrophoneAuthorization() else {
            errorMessage = "Microphone permission is required for dictation."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device dictation is not available for the current language. You can still type this capture."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        self.transcript = self.initialText.isEmpty ? spoken : "\(self.initialText) \(spoken)"
                        if result.isFinal { self.stop() }
                    }
                    if let error, self.isRecording {
                        self.errorMessage = error.localizedDescription
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
