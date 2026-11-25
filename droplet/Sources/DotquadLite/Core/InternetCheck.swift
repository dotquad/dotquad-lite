//
//  InternetCheck.swift
//  DotquadLite
//
//  Whether the internet works, not just the network. Droppy's own No internet
//  HUD covers the Mac going offline; this covers what it can't see: Wi-Fi or
//  Ethernet connected, but nothing loads, or a network that wants you to sign
//  in first.
//
//  The check asks captive.apple.com for the page macOS itself asks for when it
//  joins a network. Nothing about the user is sent. It's plain HTTP, the only
//  way Apple serves it, so it goes over a Network framework connection: a
//  sign-in page can only answer plain HTTP.
//

import Foundation
import Network

/// How the internet is doing.
public enum Connectivity: String, Sendable, Equatable {
    /// Apple's page answered.
    case online
    /// The Mac has no network at all. Droppy's own HUD says so.
    case offline
    /// Connected, but the page didn't answer.
    case noInternet = "no-internet"
    /// Connected, but something else answered: a sign-in page.
    case signIn = "sign-in"

    /// Whether something's wrong.
    public var isOut: Bool { self != .online }
}

public enum InternetCheck {
    public static let host = "captive.apple.com"
    public static let path = "/hotspot-detect.html"
    public static let timeout: TimeInterval = 6

    /// What an answer from Apple's page says. A sign-in page answers with a
    /// redirect or a page of its own, never Apple's "Success".
    public static func read(response: String?) -> Connectivity {
        guard let response, !response.isEmpty else { return .noInternet }
        let head = response.prefix(64)
        if head.hasPrefix("HTTP/1.1 200") || head.hasPrefix("HTTP/1.0 200"),
           response.contains("<TITLE>Success</TITLE>") {
            return .online
        }
        return .signIn
    }

    /// Asks Apple's page, off the main actor. Never throws: a failure is the
    /// answer.
    public static func run() async -> Connectivity {
        read(response: await fetch())
    }

    private static func fetch() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            Probe(continuation).start()
        }
    }
}

/// One request to Apple's page. Everything runs on its own serial queue, and
/// the continuation is resumed exactly once.
private final class Probe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.dotquad.lite.internet", qos: .utility)
    private let connection = NWConnection(host: NWEndpoint.Host(InternetCheck.host), port: 80, using: .tcp)
    private var continuation: CheckedContinuation<String?, Never>?
    private var received = Data()

    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }

    func start() {
        queue.asyncAfter(deadline: .now() + InternetCheck.timeout) { self.finish(nil) }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: self.send()
            case .failed, .waiting: self.finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func send() {
        let request = "GET \(InternetCheck.path) HTTP/1.1\r\nHost: \(InternetCheck.host)\r\nUser-Agent: DotquadLite\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
            if error != nil { self.finish(nil) } else { self.receive() }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, done, error in
            if let data { self.received.append(data) }
            if done || error != nil || self.received.count > 64_000 {
                self.finish(String(decoding: self.received, as: UTF8.self))
            } else {
                self.receive()
            }
        }
    }

    /// Runs on the queue. The first caller wins; the rest do nothing.
    private func finish(_ value: String?) {
        guard let continuation else { return }
        self.continuation = nil
        connection.cancel()
        continuation.resume(returning: value)
    }
}

// MARK: - Alerts

public extension IPChange {
    /// The alert for the internet changing, or nil. Plain offline says
    /// nothing: Droppy's own HUD does. Coming back says "Back online" only
    /// after Dotquad Lite said it was out.
    static func internetAlert(old: Connectivity?, new: Connectivity, network: LocalNetwork?, outFor: TimeInterval?) -> IPAlert? {
        guard let old, old != new else { return nil }
        let place = network?.kind ?? network?.interface ?? "the network"
        switch new {
        case .noInternet:
            return IPAlert(
                kind: .internet, title: "No internet",
                body: "Connected to \(place), but nothing loads. Dotquad Lite keeps checking.",
                symbol: "wifi.exclamationmark", short: "No internet", isWarning: true
            )
        case .signIn:
            return IPAlert(
                kind: .internet, title: "Sign in to this network",
                body: "\(place) is connected, but it wants you to sign in before anything loads.",
                symbol: "wifi.exclamationmark", short: "Sign in", isWarning: true
            )
        case .online:
            guard old == .noInternet || old == .signIn else { return nil }
            return IPAlert(
                kind: .internet, title: "Back online",
                body: outFor.map { "The internet was out \(LiteText.outFor($0))." } ?? "The internet works again.",
                symbol: "wifi", short: "Online"
            )
        case .offline:
            return nil
        }
    }
}

public extension LiteText {
    /// "for under a minute", "for 4 min", "for 2 hr".
    static func outFor(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "for under a minute" }
        if minutes < 60 { return "for \(minutes) min" }
        return "for \(minutes / 60) hr"
    }
}
