//
//  IPChange.swift
//  DotquadLite
//
//  Deciding when an address changed, and what the alert says. No DroppyKit,
//  so the tests check every case.
//
//  Only a change between two known answers counts: the first answer after
//  Droppy starts, or after lookups are turned on, is not a change.
//

import Foundation

/// An alert to show, as words. The Droplet turns it into Droppy's banner.
public struct IPAlert: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case publicIP = "public-ip"
        case localIP = "local-ip"
    }

    public let kind: Kind
    public let title: String
    public let body: String
    /// An SF Symbol for the banner.
    public let symbol: String
}

public enum IPChange {
    /// The alert for a new public answer, or nil when nothing the user asked
    /// about changed. `ipChanges` and `vpnChanges` are their two switches.
    /// When the VPN turned off or on and the user asked about that, the VPN
    /// is what the alert says: it's the one people care about.
    public static func publicAlert(
        old: LiteMe?,
        new: LiteMe,
        ipChanges: Bool = true,
        vpnChanges: Bool = true
    ) -> IPAlert? {
        guard let old, old.ip != new.ip || old.vpn != new.vpn else { return nil }
        let details = [LiteText.shortPlace(new), new.owner].compactMap { $0 }.joined(separator: " · ")
        let move = old.ip == new.ip ? new.ip : "\(old.ip) → \(new.ip)"
        let body = details.isEmpty ? move : "\(move)\n\(details)"

        if vpnChanges, old.vpn == true, new.vpn == false {
            return IPAlert(kind: .publicIP, title: "VPN is off", body: body, symbol: "lock.open")
        }
        if vpnChanges, old.vpn != true, new.vpn == true {
            return IPAlert(kind: .publicIP, title: "VPN is on", body: body, symbol: "lock.shield")
        }
        guard ipChanges, old.ip != new.ip else { return nil }
        return IPAlert(kind: .publicIP, title: "Public IP changed", body: body, symbol: "network")
    }

    /// The alert for a new local address, or nil. Going offline, or coming
    /// back with the same address, isn't a change.
    public static func localAlert(old: LocalNetwork?, new: LocalNetwork?) -> IPAlert? {
        guard let before = old?.address, let new, let after = new.address, before != after else { return nil }
        let place = new.kind ?? new.interface
        return IPAlert(
            kind: .localIP,
            title: "Local IP changed",
            body: "\(before) → \(after)\n\(place)" + (new.router.map { " · router \($0)" } ?? ""),
            symbol: new.symbol
        )
    }
}
