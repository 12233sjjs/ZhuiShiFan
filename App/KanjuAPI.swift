import Foundation
import CryptoKit

actor KanjuAPI {
    static let shared = KanjuAPI()
    static let primaryOrigin = URL(string: "https://kanju17.com")!
    static let backupOrigin = URL(string: "https://kanju21.com")!
    private(set) var origin = primaryOrigin
    // Public web-client request-signing protocol, verified 2026-10-22.
    // This is not an account credential. Server account/quota checks still apply.
    static let signingKey = "557d0e4ae929f438da6bd84412374e6086b8af09b3fed54bf22601d5bf8c54a0"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func account() async throws -> AccountProfile { try await request("/v1/users/me") }

    func login(account: String, password: String) async throws -> AccountProfile {
        let body = try JSONSerialization.data(withJSONObject: ["account": account, "password": password])
        let _: LoginResponse = try await request("/v1/users/password/login", body: body)
        let profile = try await self.account()
        guard profile.authenticated else {
            throw SiteError(message: "登录请求已提交，但会话尚未确认，请重试。", status: nil)
        }
        return profile
    }

    func useBackup() { origin = Self.backupOrigin }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func signature(method: String, path: String, timestamp: String, nonce: String) -> String {
        let text = "\(method)\n\(path)\n\(timestamp)\n\(nonce)"
        return HMAC<SHA256>.authenticationCode(for: Data(text.utf8),
            using: SymmetricKey(data: Data(signingKey.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    static func path(_ path: String, query: [(String, String)] = []) -> String {
        guard !query.isEmpty else { return path }
        return path + "?" + query.map { "\(component($0.0))=\(component($0.1))" }.joined(separator: "&")
    }

    func home(cursor: String? = nil) async throws -> Feed {
        var query = [("scope", "public"), ("mode", cursor == nil ? "preview" : "page"),
                     ("sections", "3"), ("cards", "12")]
        if let cursor { query.append(("cursor", cursor)) }
        return try await request(Self.path("/v1/feed/home", query: query))
    }

    func search(_ text: String, page: Int = 1, cursor: String? = nil) async throws -> BrowsePage {
        var query = [("q", text), ("page", String(page)), ("limit", "20")]
        if let cursor { query.append(("cursor", cursor)) }
        return try await request(Self.path("/v1/browse/catalog", query: query))
    }

    func detail(_ id: String) async throws -> Movie {
        try await request("/v1/catalog/" + Self.component(id))
    }

    func episodes(_ id: String, offset: Int) async throws -> EpisodePage {
        try await request(Self.path("/v1/catalog/" + Self.component(id) + "/episodes",
                                    query: [("offset", String(offset)), ("limit", "48")]))
    }

    func lines(for episode: Episode, movie: Movie) async throws -> [PlaybackLine] {
        guard let token = episode.token, !token.isEmpty else {
            throw SiteError(message: "这一集暂时没有播放地址。", status: nil)
        }
        var query = [("view", "compact")]
        if let number = episode.number { query.append(("episode_index", String(number))) }
        if let count = movie.availableEpisodeCount { query.append(("episode_count", String(count))) }
        if let kind = movie.contentKind { query.append(("content_kind", kind)) }
        let result: Playback = try await request(Self.path("/v1/playback/resolve/" + Self.component(token), query: query))
        guard !result.lineOptions.isEmpty else {
            throw SiteError(message: "网站暂未提供可用线路。", status: nil)
        }
        return result.lineOptions
    }

    func resolve(_ line: PlaybackLine) async throws -> PlaybackLine {
        if let ticket = line.ticket {
            let data = try JSONSerialization.data(withJSONObject: ["ticket": ticket])
            let response: ResolvedPlayback = try await request("/v1/playback/resolve-line?view=compact", body: data)
            guard response.line.mediaURL != nil, response.line.ticket == nil else {
                throw SiteError(message: "这条线路没有返回可播放的视频，请切换线路。", status: nil)
            }
            return response.line
        }
        guard line.mediaURL != nil else {
            throw SiteError(message: "此线路暂不支持原生播放，请切换线路。", status: nil)
        }
        return line
    }

    private func request<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        let attemptedOrigin = origin
        do { return try await perform(path, body: body, origin: attemptedOrigin) }
        catch {
            guard Self.shouldFailover(error), attemptedOrigin == Self.primaryOrigin else { throw error }
            origin = Self.backupOrigin
            // Resolving a line can consume site quota. Never replay an ambiguous POST.
            guard body == nil else {
                throw SiteError(message: "主站连接失败，已切换备用站。请重新提交当前操作。", status: nil)
            }
            return try await perform(path, body: nil, origin: Self.backupOrigin)
        }
    }

    static func shouldFailover(_ error: Error) -> Bool {
        if let error = error as? SiteError, let status = error.status { return status >= 500 }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .secureConnectionFailed, .serverCertificateUntrusted,
                .serverCertificateHasBadDate, .badServerResponse].contains(error.code)
    }

    private func perform<T: Decodable>(_ path: String, body: Data?, origin: URL) async throws -> T {
        let url = URL(string: path, relativeTo: origin)!.absoluteURL
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: body == nil && !path.contains("/playback/") ? 15 : 45)
        let method = body == nil ? "GET" : "POST"
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue(timestamp, forHTTPHeaderField: "x-ai-movie-timestamp")
        request.setValue(nonce, forHTTPHeaderField: "x-ai-movie-nonce")
        request.setValue(Self.signature(method: method, path: path, timestamp: timestamp, nonce: nonce),
                         forHTTPHeaderField: "x-ai-movie-signature")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.serverError(data, status: http.statusCode)
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true else {
            throw URLError(.badServerResponse)
        }
        do { return try Self.decoder().decode(T.self, from: data) }
        catch { throw SiteError(message: "网站数据格式发生变化，暂时无法读取。", status: http.statusCode) }
    }

    static func serverError(_ data: Data, status: Int) -> SiteError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? object?["message"] as? String
        let fallback: String
        switch status {
        case 401, 403: fallback = "网站拒绝了请求，可能需要登录或接口已更新。"
        case 402: fallback = "网站播放额度不足，请在网站账户中确认额度。"
        case 429: fallback = "请求太频繁，请稍后再试。"
        default: fallback = "网站暂时无法响应（\(status)），请稍后重试。"
        }
        return SiteError(message: message.map { fallback + "\n" + $0 } ?? fallback, status: status)
    }
}
