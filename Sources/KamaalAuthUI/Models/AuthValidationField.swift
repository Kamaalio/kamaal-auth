public struct KamaalAuthValidationIssue: Equatable, Sendable {
    public let field: AuthValidationField
    public let message: String

    public init(field: AuthValidationField, message: String) {
        self.field = field
        self.message = message
    }
}

public enum AuthValidationField: String, Hashable, Sendable {
    case email
    case verifyEmail
    case password
    case verifyPassword
    case name
}
