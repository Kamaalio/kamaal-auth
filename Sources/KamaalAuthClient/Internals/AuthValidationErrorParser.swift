//
//  AuthValidationErrorParser.swift
//  KamaalAuth
//

import Foundation

enum AuthValidationErrorParser {
    /// Pulls field-level validation issues out of an error body.
    ///
    /// Returns an empty array when the body carries no `context.validations`, which the UI reads as "show a general
    /// error rather than field errors".
    static func parseIssues(from data: Data) -> [AuthValidationIssue] {
        guard let response = try? Wire.makeDecoder().decode(Wire.ErrorResponse.self, from: data) else { return [] }

        return parseIssues(from: response)
    }

    static func parseIssues(from response: Wire.ErrorResponse) -> [AuthValidationIssue] {
        guard let validations = response.context?.validations else { return [] }

        return validations.map { issue in
            AuthValidationIssue(
                code: issue.code,
                path: issue.path.compactMap(pathComponent(from:)),
                message: issue.message,
            )
        }
    }

    static func errorCode(from data: Data) -> String? {
        try? Wire.makeDecoder().decode(Wire.ErrorResponse.self, from: data).code
    }

    private static func pathComponent(from value: AuthJSONValue) -> String? {
        switch value {
        case .string(let string): string
        case .number(let number): String(Int(number))
        default: nil
        }
    }
}
