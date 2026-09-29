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
        .onKeyPress(keys: [.return, .space], phases: [.down, .repeat, .up]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            guard focused.wrappedValue else { return .ignored }
            guard !isLoading else { return .handled }
            if press.phase == .down { action() }
            return .handled
        }
        .disabled(isLoading)
    }
}
