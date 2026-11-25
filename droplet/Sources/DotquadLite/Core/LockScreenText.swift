//
//  LockScreenText.swift
//  DotquadLite
//
//  What Dotquad Lite's row on Droppy's lock screen says. No DroppyKit, so the
//  tests check every case.
//
//  A lock screen is the one place anyone walking past can read, so the row
//  says whether the VPN is on and the country, never the IP, unless the user
//  turns that on separately.
//

import Foundation

/// One lock screen row, in both of Droppy's styles: the strip (symbol, text,
/// detail) and the rounded ring (a short value inside, a caption under it).
public struct LockLine: Equatable, Sendable {
    public let symbol: String
    public let text: String
    public let detail: String?
    /// Inside the ring, a 22-point box: two or three characters at most.
    /// Nil shows the symbol instead.
    public let center: String?
    public let bottom: String
}

public enum LockScreenText {
    /// The row for the current state. The internet being out comes first,
    /// as in the live activity.
    public static func line(
        vpnOn: Bool,
        connectivity: Connectivity?,
        country: String?,
        ip: String?,
        showIP: Bool
    ) -> LockLine {
        switch connectivity {
        case .offline?:
            return LockLine(symbol: "wifi.slash", text: "Offline", detail: nil, center: nil, bottom: "Offline")
        case .noInternet?:
            return LockLine(symbol: "wifi.exclamationmark", text: "No internet", detail: nil, center: nil, bottom: "No internet")
        case .signIn?:
            return LockLine(symbol: "wifi.exclamationmark", text: "Sign in to Wi-Fi", detail: nil, center: nil, bottom: "Sign in")
        default:
            break
        }
        let code = country.flatMap { $0.count == 2 ? $0.uppercased() : nil }
        let detail = showIP ? (ip ?? code) : code
        return vpnOn
            ? LockLine(symbol: "lock.shield.fill", text: "VPN on", detail: detail, center: code, bottom: "VPN on")
            : LockLine(symbol: "network", text: "No VPN", detail: detail, center: code, bottom: "No VPN")
    }
}
