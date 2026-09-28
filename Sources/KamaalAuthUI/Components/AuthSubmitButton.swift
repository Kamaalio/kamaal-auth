import KamaalUI
import SwiftUI

struct AuthSubmitButton: View {
    private let title: String
    private let isLoading: Bool
    private let focused: FocusState<Bool>.Binding
    private let action: () -> Void

    init(title: String, isLoading: Bool, focused: FocusState<Bool>.Binding, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.focused = focused
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading { ProgressView().controlSize(.small) }
                Text(title).ktakeWidthEagerly()
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .focusable()
        .focused(focused)
        .disabled(isLoading)
    }
}
