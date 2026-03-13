import SwiftUI

struct AudioPlaybackView: View {
    let audioPath: String
    @State private var audioPlayer = AudioPlayer()
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            if audioPlayer.hasAudio {
                HStack(spacing: 16) {
                    Button { audioPlayer.toggle() } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.recallPrimary)
                    }

                    VStack(spacing: 4) {
                        ProgressView(value: audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0)
                            .tint(Color.recallPrimary)

                        HStack {
                            Text(audioPlayer.currentTime.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(audioPlayer.duration.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Button {
                    if audioPlayer.load(sessionAudioPath: audioPath) {
                        audioPlayer.play()
                    } else {
                        toastMessage = "Audio file not available"
                        showToast = true
                    }
                } label: {
                    Label("Play Recording", systemImage: "play.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.recallPrimary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .toast(isPresented: $showToast, message: toastMessage)
        .onDisappear {
            audioPlayer.stop()
        }
    }
}
