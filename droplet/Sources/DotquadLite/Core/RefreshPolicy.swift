//
//  RefreshPolicy.swift
//  DotquadLite
//
//  When Dotquad Lite may ask dotquad.app again. The rules, from the spec:
//
//  - at most once every 5 minutes, and only while someone is looking;
//  - once more after the network changes, after a random 0-30 s wait, so
//    thousands of Macs reconnecting after a VPN server restart don't all ask
//    at once;
//  - never before a 429's Retry-After has passed.
//

import Foundation

public struct RefreshPolicy: Equatable, Sendable {
    public static let minInterval: TimeInterval = 5 * 60
    public static let maxJitter: TimeInterval = 30

    public private(set) var lastAttempt: Date?
    public private(set) var blockedUntil: Date?
    /// The network changed since the last request, so the last answer may be wrong.
    public private(set) var networkChanged = false

    public init() {}

    /// Whether a request may go out now.
    public func mayFetch(now: Date) -> Bool {
        if let blockedUntil, now < blockedUntil { return false }
        if networkChanged { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.minInterval
    }

    /// Whether an answer from `date` is still good enough to hand out without asking.
    public func isFresh(_ date: Date?, now: Date) -> Bool {
        guard let date, !networkChanged else { return false }
        return now.timeIntervalSince(date) < Self.minInterval
    }

    /// Seconds until a 429 stops blocking, or nil when nothing blocks.
    public func blockedFor(now: Date) -> TimeInterval? {
        guard let blockedUntil, now < blockedUntil else { return nil }
        return blockedUntil.timeIntervalSince(now)
    }

    public mutating func didAttempt(at now: Date) {
        lastAttempt = now
        networkChanged = false
    }

    public mutating func didRateLimit(retryAfter: TimeInterval, now: Date) {
        blockedUntil = now.addingTimeInterval(retryAfter)
    }

    public mutating func networkDidChange() {
        networkChanged = true
    }

    /// Forget everything, for when the user switches lookups off.
    public mutating func reset() {
        self = RefreshPolicy()
    }

    /// The wait before asking after a network change: 0-30 s, uniform.
    public static func jitter<G: RandomNumberGenerator>(using generator: inout G) -> TimeInterval {
        TimeInterval.random(in: 0...maxJitter, using: &generator)
    }

    public static func jitter() -> TimeInterval {
        var generator = SystemRandomNumberGenerator()
        return jitter(using: &generator)
    }
}
