import Testing

@testable import KamaalAuthUI

@Suite("KamaalAuth Validator Tests")
struct KamaalAuthValidatorTests {
    @Test(arguments: ["jane.doe+cards@example.co.uk", "jane@example.com"])
    func `Accepts server compatible emails`(_ email: String) { #expect(KamaalAuthValidator.emailIssue(email) == nil) }

    @Test(arguments: ["invalid", ".jane@example.com", "jane..doe@example.com", "jane@example.c"])
    func `Rejects invalid emails`(_ email: String) { #expect(KamaalAuthValidator.emailIssue(email)?.field == .email) }

    @Test
    func `Uses password boundaries`() {
        #expect(KamaalAuthValidator.passwordIssue(String(repeating: "a", count: 8)) == nil)
        #expect(KamaalAuthValidator.passwordIssue(String(repeating: "a", count: 129))?.field == .password)
    }
}
