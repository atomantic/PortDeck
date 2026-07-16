import Foundation
import AVFoundation
import Observation

@Observable
final class AudioRecorder {
    var isRecording = false
    var isPaused = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var chunkIndex = 0
    private var currentSessionID: String?
    private var chunkDuration: TimeInterval = 300 // 5 minutes
    private var chunkStartTime: Date?
    private var recordingStartTime: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var lastLevelUpdate: Date = .distantPast

    private let recordingsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Recordings")

    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording(sessionID: String) {
        currentSessionID = sessionID
        chunkIndex = 0
        elapsedTime = 0
        pausedAccumulated = 0

        let sessionDir = recordingsDirectory.appendingPathComponent(sessionID)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? audioSession.setActive(true)

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        guard let recordingFormat else { return }

        let outputURL = sessionDir.appendingPathComponent("chunk_\(String(format: "%03d", chunkIndex)).m4a")
        audioFile = try? AVAudioFile(forWriting: outputURL, settings: Self.outputSettings)
        chunkStartTime = Date()

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRecording, !self.isPaused else { return }

            // Calculate RMS audio level, throttled to ~10Hz
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))

            let now = Date()
            if now.timeIntervalSince(self.lastLevelUpdate) >= 0.1 {
                self.lastLevelUpdate = now
                DispatchQueue.main.async {
                    self.audioLevel = rms
                }
            }

            // Convert and write
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * recordingFormat.sampleRate / inputFormat.sampleRate))
            guard let convertedBuffer else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            try? self.audioFile?.write(from: convertedBuffer)
        }

        try? audioEngine.start()
        isRecording = true
        recordingStartTime = Date()

        RecallLogger.recording("Started recording session: \(sessionID)")

        startTimer()
    }

    func stopRecording() -> URL? {
        guard let currentSessionID else { return nil }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioFile = nil
        audioEngine = nil

        isRecording = false
        isPaused = false
        timer?.invalidate()
        timer = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        let sessionDir = recordingsDirectory.appendingPathComponent(currentSessionID)
        RecallLogger.recording("Stopped recording session: \(currentSessionID), duration: \(String(format: "%.0f", elapsedTime))s")

        self.currentSessionID = nil
        return sessionDir
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        if let start = recordingStartTime {
            pausedAccumulated += Date().timeIntervalSince(start)
        }
        recordingStartTime = nil
        audioEngine?.pause()
        timer?.invalidate()
        RecallLogger.recording("Paused recording")
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        recordingStartTime = Date()
        try? audioEngine?.start()
        startTimer()
        RecallLogger.recording("Resumed recording")
    }

    private func rotateChunk() {
        guard let currentSessionID else { return }

        audioFile = nil
        chunkIndex += 1

        let sessionDir = recordingsDirectory.appendingPathComponent(currentSessionID)
        let outputURL = sessionDir.appendingPathComponent("chunk_\(String(format: "%03d", chunkIndex)).m4a")

        audioFile = try? AVAudioFile(forWriting: outputURL, settings: Self.outputSettings)
        chunkStartTime = Date()

        RecallLogger.recording("Rotated to chunk \(chunkIndex)")
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = self.pausedAccumulated + Date().timeIntervalSince(start)

            // Check chunk duration in timer instead of audio callback
            if let chunkStart = self.chunkStartTime,
               Date().timeIntervalSince(chunkStart) >= self.chunkDuration {
                self.rotateChunk()
            }
        }
    }
}
