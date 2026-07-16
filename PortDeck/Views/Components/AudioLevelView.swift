import SwiftUI

struct AudioLevelView: View {
    let level: Float
    let barCount: Int = 20
    @State private var barOffsets: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 0.6...1.0) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 40)
        .onChange(of: level) { _, _ in
            for i in 0..<barCount {
                barOffsets[i] = CGFloat.random(in: 0.6...1.0)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = CGFloat(min(level * 5, 1.0))
        let threshold = CGFloat(index) / CGFloat(barCount)
        let active = normalizedLevel > threshold
        return active ? 40 * barOffsets[index] * normalizedLevel : 4
    }

    private func barColor(for index: Int) -> Color {
        let ratio = CGFloat(index) / CGFloat(barCount)
        if ratio < 0.6 { return .recallSuccess }
        if ratio < 0.8 { return .recallWarning }
        return .recallRecording
    }
}

#Preview {
    AudioLevelView(level: 0.5)
}
