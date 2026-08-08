import SwiftUI

struct AuthSignInHeader: View {
    let mode: AuthSignInScreenModel.Mode
    let configuration: KamaalAuthConfiguration

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: configuration.symbolName).font(.system(size: 52)).foregroundStyle(.tint)
            Text(configuration.title).font(.largeTitle.bold())
            Text(mode == .login ? configuration.signInSubtitle : configuration.signUpSubtitle).foregroundStyle(
                .secondary)
        }
    }
}
