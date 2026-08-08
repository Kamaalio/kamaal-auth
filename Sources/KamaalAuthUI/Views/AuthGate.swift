import KamaalUI
import SwiftUI

extension View {
    /// Presents the shared authentication screen until `auth` has loaded a session.
    ///
    /// - Example:
    ///   ```swift
    ///   Text("Signed in").kamaalAuth(auth)
    ///   ```
    public func kamaalAuth(_ auth: KamaalAuth) -> some View { modifier(KamaalAuthEnvironmentModifier(auth: auth)) }
}

private struct KamaalAuthEnvironmentModifier: ViewModifier {
    @State private var auth: KamaalAuth

    init(auth: KamaalAuth) { self.auth = auth }

    func body(content: Content) -> some View {
        KJustStack {
            if auth.initiallyValidatingToken {
                ProgressView()
            } else if !auth.isLoggedIn {
                NavigationStack { AuthSignInScreen(configuration: auth.configuration) }
            } else {
                content
            }
        }
        .environment(auth)
    }
}
