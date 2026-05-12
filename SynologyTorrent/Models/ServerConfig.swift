import Foundation

struct ServerConfig: Codable, Equatable {
    var scheme: Scheme
    var host: String
    var port: Int
    var account: String

    enum Scheme: String, Codable, CaseIterable, Identifiable {
        case http, https
        var id: String { rawValue }
    }

    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = host
        components.port = port
        return components.url
    }

    static let `default` = ServerConfig(scheme: .https, host: "", port: 5001, account: "")
}
