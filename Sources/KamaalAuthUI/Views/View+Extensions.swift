import SwiftUI

extension View {
    @ViewBuilder
    func authEmailInput() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}
