import Foundation

/// Configures the app-specific branding and persistence used by ``KamaalAuth``.
///
/// - Example:
///   ```swift
///   let configuration = KamaalAuthConfiguration(appName: "TCG")
///   ```
public struct KamaalAuthConfiguration: Sendable {
    /// The app name used to derive the default title and storage namespace.
    public let appName: String
    /// The title shown above the authentication form.
    public let title: String
    /// The subtitle shown while signing in.
    public let signInSubtitle: String
    /// The subtitle shown while creating an account.
    public let signUpSubtitle: String
    /// The SF Symbol shown above the authentication form.
    public let symbolName: String
    /// The namespace used for the cached session in `UserDefaults`.
    public let storageNamespace: String
    /// The delay before an authentication error toast is dismissed.
    public let toastDismissalDelay: Duration

    /// Creates configuration with defaults derived from `appName`.
    ///
    /// - Example:
    ///   ```swift
    ///   let configuration = KamaalAuthConfiguration(appName: "TCG", title: "Welcome to TCG")
    ///   ```
    public init(
        appName: String,
        title: String? = nil,
        signInSubtitle: String? = nil,
        signUpSubtitle: String? = nil,
        symbolName: String = "person.crop.circle.badge.checkmark",
        storageNamespace: String? = nil,
        toastDismissalDelay: Duration = .seconds(3)
    ) {
        self.appName = appName
        self.title = title ?? String(localized: "Welcome to \(appName)")
        self.signInSubtitle = signInSubtitle ?? String(localized: "Sign in to continue.")
        self.signUpSubtitle = signUpSubtitle ?? String(localized: "Create an account to get started.")
        self.symbolName = symbolName
        self.storageNamespace = storageNamespace ?? "\(Bundle.main.bundleIdentifier ?? appName).KamaalAuth"
        self.toastDismissalDelay = toastDismissalDelay
    }
}
