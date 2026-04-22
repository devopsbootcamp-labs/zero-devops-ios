import Foundation

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : msg
        case .decodingFailed(let e):        return "Decode error: \(e.localizedDescription)"
        case .invalidResponse:              return "Invalid server response"
        case .notAuthenticated:             return "Not authenticated"
        }
    }
}

// MARK: - Envelope wrappers (mirrors Android response fallback parsing)

private struct Envelope<T: Decodable>: Decodable {
    let data:          T?
    let results:       T?
    let items:         T?
    let accounts:      T?
    let cloudAccounts: T?
    let deployments:   T?
    let resources:     T?
    let providers:     T?
    let trends:        T?
    let activity:      T?
    let insights:      T?
    let failures:      T?
    let blueprints:    T?
    let notifications: T?
    let alerts:        T?
}

// MARK: - APIClient

/// URLSession-based HTTP client — mirrors Android Retrofit + AuthInterceptor.
final class APIClient {

    static let shared = APIClient()

    private let baseURL = URL(string: AppConfig.apiBaseURL)!
    private let sessionManager = AuthSessionManager.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy  = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            let fmts = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
            ]
            let fmt = DateFormatter()
            for f in fmts {
                fmt.dateFormat = f
                if let date = fmt.date(from: raw) { return date }
            }
            return Date()
        }
        return d
    }()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - HTTP verbs

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(method: "GET", path: path, body: Optional<EmptyBody>.none)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await perform(method: "POST", path: path, body: body)
    }

    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await perform(method: "PUT", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await perform(method: "DELETE", path: path, body: Optional<EmptyBody>.none)
    }

    /// Mirrors Android `fetchDeploymentsScoped`: prefer account-scoped endpoints, then fallback.
    /// Properly encodes dynamic path components.
    func fetchDeploymentsScoped(accountId: String?, limit: Int = 500) async throws -> [Deployment] {
        let scoped = accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
            .flatMap { $0.isEmpty ? nil : $0 }

        var lastError: Error?
        if let scoped, let encodedId = Self.percentEncode(scoped) {
            let scopedPaths = [
                "api/v1/cloud-accounts/\(encodedId)/deployments?limit=\(limit)",
                "api/v1/deployments?limit=\(limit)&cloud_account_id=\(encodedId)",
                "api/v1/deployments?cloud_account_id=\(encodedId)&limit=\(limit)",
            ]
            for path in scopedPaths {
                do {
                    return try await get(path)
                } catch {
                    lastError = error
                }
            }
        }

        let tenantPaths = [
            "api/v1/deployments?limit=\(limit)",
            "api/v1/deployments",
        ]
        for path in tenantPaths {
            do {
                return try await get(path)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }
    
    /// Percent-encode path component for URL safety (RFC 3986).
    private static func percentEncode(_ component: String) -> String? {
        // Encode all except unreserved characters: A-Z a-z 0-9 - . _ ~
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return component.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
    
    /// Build a query parameter string with proper encoding.
    /// Example: buildQueryString(["cloud_account_id": "acct-123", "limit": "500"])
    /// Returns: "cloud_account_id=acct-123&limit=500" (with unsafe characters encoded)
    static func buildQueryString(_ params: [String: String]) -> String? {
        let encoded = params.compactMap { key, value -> String? in
            guard let k = percentEncode(key), let v = percentEncode(value) else { return nil }
            return "\(k)=\(v)"
        }
        return encoded.isEmpty ? nil : encoded.joined(separator: "&")
    }
    
    /// Build a path segment with proper encoding for a single component.
    /// Example: encodePathComponent("acct-123/special") -> "acct-123%2Fspecial"
    static func encodePathComponent(_ component: String) -> String? {
        return percentEncode(component)
    }

    // MARK: - Core

    private func perform<B: Encodable, T: Decodable>(method: String, path: String, body: B?) async throws -> T {
        let first = try buildRequest(method: method, path: path, body: body, useFreshToken: false)
        let (data, response) = try await urlSession.data(for: first)

        do {
            try validate(response: response, data: data)
            return try decodeAny(data)
        } catch APIError.httpError(let statusCode, _) where statusCode == 401 {
            // Mirror Android TokenRefreshAuthenticator behavior: refresh once and retry.
            _ = try await sessionManager.refreshAccessToken()
            let retry = try buildRequest(method: method, path: path, body: body, useFreshToken: true)
            let (retryData, retryResponse) = try await urlSession.data(for: retry)
            try validate(response: retryResponse, data: retryData)
            return try decodeAny(retryData)
        }
    }

    private func buildRequest<B: Encodable>(method: String, path: String, body: B?, useFreshToken: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = useFreshToken ? sessionManager.currentBundle()?.accessToken : sessionManager.currentAccessToken()
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let tid = sessionManager.currentTenantId() {
            req.setValue(tid, forHTTPHeaderField: "x-tenant-id")
        }
        // Do NOT attach x-account-id for aggregate/drift/jobs endpoints.
        if let aid = sessionManager.currentAccountId(), shouldAttachAccountHeader(path: path) {
            req.setValue(aid, forHTTPHeaderField: "x-account-id")
        }
        if let body = body, !(body is EmptyBody) {
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    private func shouldAttachAccountHeader(path: String) -> Bool {
        let pathOnly = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let normalized = pathOnly.hasPrefix("/") ? pathOnly : "/\(pathOnly)"

        // Keep aggregate/list endpoints tenant-scoped to match web behavior.
        if normalized.hasPrefix("/api/v1/cloud/accounts") { return false }
        if normalized.hasPrefix("/api/v1/accounts") { return false }
        if normalized.hasPrefix("/api/v1/analytics") { return false }
        if normalized.hasPrefix("/api/v1/dashboard") { return false }
        if normalized.hasPrefix("/api/v1/cost") { return false }
        if normalized.hasPrefix("/api/v1/resources") { return false }
        if normalized.hasPrefix("/api/v1/inventory") { return false }
        if normalized.hasPrefix("/api/v1/drift/posture") { return false }
        if normalized.hasPrefix("/api/v1/drift/deployments") { return false }
        if normalized.hasPrefix("/api/v1/drift/jobs") { return false }

        // Avoid duplicate account scoping when account is already in path.
        if normalized.range(of: "^/api/v1/cloud-accounts/[^/]+/deployments$", options: .regularExpression) != nil {
            return false
        }
        if normalized.range(of: "^/api/v1/cloud-accounts/[^/]+/cost/.*$", options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = extractErrorMessage(from: data)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }
    }

    private func extractErrorMessage(from data: Data) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["message", "error", "detail", "reason"]
            for key in keys {
                if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            if let errors = dict["errors"] as? [String], let first = errors.first, !first.isEmpty {
                return first
            }
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw.count > 180 ? String(raw.prefix(180)) + "..." : raw
        }
        return ""
    }

    private func decodeAny<T: Decodable>(_ data: Data) throws -> T {
        // Direct decode
        if let value = try? decoder.decode(T.self, from: data) { return value }
        // Try envelope
        if let env = try? decoder.decode(Envelope<T>.self, from: data) {
            if let value = env.data { return value }
            if let value = env.results { return value }
            if let value = env.items { return value }
            if let value = env.accounts { return value }
            if let value = env.cloudAccounts { return value }
            if let value = env.deployments { return value }
            if let value = env.resources { return value }
            if let value = env.providers { return value }
            if let value = env.trends { return value }
            if let value = env.activity { return value }
            if let value = env.insights { return value }
            if let value = env.failures { return value }
            if let value = env.blueprints { return value }
            if let value = env.notifications { return value }
            if let value = env.alerts { return value }
        }
        // Empty body
        if T.self == EmptyResponse.self, let v = EmptyResponse() as? T { return v }
        throw APIError.decodingFailed(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "No decodable content")
        ))
    }
}

// Sentinel types
private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable { init?() {} }
