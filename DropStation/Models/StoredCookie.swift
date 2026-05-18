import Foundation

/// Codable mirror of `HTTPCookie`. We need to persist DSM session
/// cookies across launches (for the Secure SignIn web flow), but
/// `HTTPCookie` itself can't be Codable directly — it's an NSObject
/// subclass with a property-list-based API. This struct captures just
/// the fields we care about for round-tripping a sign-in.
struct StoredCookie: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(name: String, value: String, domain: String, path: String,
         expiresDate: Date?, isSecure: Bool, isHTTPOnly: Bool) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
    }

    /// Rehydrate as an `HTTPCookie` ready to drop into
    /// `HTTPCookieStorage.shared`. Returns nil if the cookie was stored
    /// with values the `HTTPCookie` initializer rejects (very unlikely
    /// given we only persist cookies we just received from the system,
    /// but the initializer is failable so we surface that honestly).
    func makeHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isHTTPOnly {
            // HTTPCookie has no public init key for HttpOnly; the only
            // way to set it via the property dict is via the
            // OriginURL/Version-1 path, which we don't need. The flag
            // is informational anyway — our URLSession code doesn't
            // distinguish.
        }
        return HTTPCookie(properties: properties)
    }
}
