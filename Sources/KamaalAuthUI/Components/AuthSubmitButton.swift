import KamaalUI
import SwiftUI

struct AuthSubmitButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void

    init(title: String, isLoading: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
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
        .disabled(isLoading)
    }
}
