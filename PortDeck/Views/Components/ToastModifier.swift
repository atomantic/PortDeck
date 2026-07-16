import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var isError: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    ToastView(message: message, isError: isError)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isPresented)
            .task(id: isPresented) {
                guard isPresented else { return }
                try? await Task.sleep(for: .seconds(2))
                isPresented = false
            }
    }
}
