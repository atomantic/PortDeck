import SwiftUI

struct ToastView: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isError ? Color.recallRecording : Color.recallSuccess)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "Saved successfully")
        ToastView(message: "Something went wrong", isError: true)
    }
}
