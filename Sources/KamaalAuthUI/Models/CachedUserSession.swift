import Foundation

struct CachedUserSession: Codable {
    let session: UserSession
    let cachedAt: Date
}
