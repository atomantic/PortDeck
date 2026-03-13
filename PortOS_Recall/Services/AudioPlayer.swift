import Foundation
import AVFoundation
import Observation

@Observable
final class AudioPlayer {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(sessionAudioPath: String) -> Bool {
        let url = URL(fileURLWithPath: sessionAudioPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            RecallLogger.error("Audio path does not exist: \(sessionAudioPath)")
            return false
        }

        // Multi-chunk directory: concatenate chunks into a temp file for playback
        // For now, play the first chunk (most sessions are single-chunk)
        let audioFileURL: URL
        if isDirectory.boolValue {
            guard let firstChunk = findChunks(in: url).first else {
                RecallLogger.error("No audio chunks found in: \(sessionAudioPath)")
                return false
            }
            audioFileURL = firstChunk
        } else {
            audioFileURL = url
        }

        guard let audioPlayer = try? AVAudioPlayer(contentsOf: audioFileURL) else {
            RecallLogger.error("Failed to create audio player for: \(audioFileURL.lastPathComponent)")
            return false
        }

        player = audioPlayer
        duration = audioPlayer.duration
        currentTime = 0

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback)
        try? audioSession.setActive(true)

        RecallLogger.info("Loaded audio for playback: \(audioFileURL.lastPathComponent)")
        return true
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    var hasAudio: Bool {
        player != nil
    }

    private func findChunks(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension == "m4a"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }
}
