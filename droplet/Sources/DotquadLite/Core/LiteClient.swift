//
//  LiteClient.swift
//  DotquadLite
//
//  One request: GET https://api.dotquad.app/lite/me. Keyless, no cookies, no
//  cache, and a User-Agent the server counts requests by.
//

import Foundation

public enum LiteError: Error, Equatable, Sendable {
    /// 429. Wait this many seconds before asking again.
    case rateLimited(retryAfter: TimeInterval)
    /// Any other status the API answered with, 503 while its data loads included.
    case unavailable(status: Int)
    /// No connection, a timeout, or DNS failure.
    case offline
    /// A 200 that didn't decode.
    case badResponse

    /// One sentence for the widget and for MCP callers.
    public var message: String {
        switch self {
        case .rateLimited(let wait):
            let minutes = max(1, Int((wait / 60).rounded(.up)))
            return "dotquad.app is busy. Dotquad Lite tries again in \(minutes) min."
        case .unavailable:
            return "dotquad.app didn't answer. Try again in a minute."
        case .offline:
            return "No connection. Dotquad Lite tries again when the network changes."
        case .badResponse:
            return "dotquad.app sent an answer Dotquad Lite can't read."
        }
    }
}

public struct LiteClient: Sendable {
    public static let endpoint = URL(string: "https://api.dotquad.app/lite/me")!
    /// Used when a 429 carries no usable `Retry-After`.
    public static let defaultRetryAfter: TimeInterval = 60
    /// The longest wait a `Retry-After` can ask for, so a bad header can't
    /// switch Lite off for good.
    public static let maxRetryAfter: TimeInterval = 3600

    private let session: URLSession
    private let userAgent: String

    public init(version: String, session: URLSession = LiteClient.makeSession()) {
        self.session = session
        self.userAgent = "DotquadLite/\(version)"
    }

    /// Ephemeral: no cookies, no URL cache, nothing written to disk.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    /// Runs off the main actor: a nonisolated async function.
    public func fetch() async throws -> LiteMe {
        var request = URLRequest(url: Self.endpoint)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LiteError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw LiteError.badResponse }
        return try Self.parse(data: data, response: http, now: Date())
    }

    /// Turns a response into an answer or a `LiteError`. Separate from the
    /// request so the tests can feed it responses.
    public static func parse(data: Data, response: HTTPURLResponse, now: Date) throws -> LiteMe {
        switch response.statusCode {
        case 200:
            guard let me = try? JSONDecoder().decode(LiteMe.self, from: data), !me.ip.isEmpty else {
                throw LiteError.badResponse
            }
            return me
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After")
            throw LiteError.rateLimited(retryAfter: retryAfter(header, now: now))
        default:
            throw LiteError.unavailable(status: response.statusCode)
        }
    }

    /// `Retry-After` as seconds, from either form the header allows (a number
    /// of seconds or an HTTP date), clamped to 1 s ... 1 hr.
    public static func retryAfter(_ header: String?, now: Date) -> TimeInterval {
        guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return defaultRetryAfter
        }
        let seconds: TimeInterval
        if let value = TimeInterval(raw), value.isFinite {
            seconds = value
        } else if let date = httpDate(raw) {
            seconds = date.timeIntervalSince(now)
        } else {
            return defaultRetryAfter
        }
        return min(max(seconds, 1), maxRetryAfter)
    }

    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}
