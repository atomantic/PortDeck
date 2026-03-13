import SwiftUI

struct ConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let destructiveLabel: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                Button(destructiveLabel, role: .destructive) {
                    onConfirm()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    func destructiveConfirmation(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        destructiveLabel: String = "Delete",
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmationDialogModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            destructiveLabel: destructiveLabel,
            onConfirm: onConfirm
        ))
    }
}
