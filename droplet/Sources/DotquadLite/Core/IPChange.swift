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

/// An alert to show, as words. The Droplet shows it as a HUD in the island
/// or as a notification, as the user chose.
public struct IPAlert: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case publicIP = "public-ip"
        case localIP = "local-ip"
        case vpn = "vpn"
        case internet = "internet"
    }

    public let kind: Kind
    public let title: String
    public let body: String
    /// An SF Symbol for the HUD and the notification.
    public let symbol: String
    /// A few words for the HUD's strip, where there's room for little else:
    /// "VPN on", "New IP".
    public let short: String
    /// Whether it's a warning: the VPN went off. Drawn in Flag amber.
    public let isWarning: Bool

    public init(kind: Kind, title: String, body: String, symbol: String, short: String, isWarning: Bool = false) {
        self.kind = kind
        self.title = title
        self.body = body
        self.symbol = symbol
        self.short = short
        self.isWarning = isWarning
    }

    static func vpnOn(_ body: String) -> IPAlert {
        IPAlert(kind: .vpn, title: "VPN is on", body: body, symbol: "lock.shield", short: "VPN on")
    }

    static func vpnOff(_ body: String) -> IPAlert {
        IPAlert(kind: .vpn, title: "VPN is off", body: body, symbol: "lock.open", short: "VPN off", isWarning: true)
    }
}

public enum IPChange {
    /// The alert for a new public answer, or nil when nothing the user asked
    /// about changed. `ipChanges` and `vpnChanges` are their two switches.
    /// When the VPN turned off or on and the user asked about that, the VPN
    /// is what the alert says: it's the one people care about.
    ///
    /// `vpnAnnounced` is true when the Mac's own tunnel already said the VPN
    /// changed a moment ago, so dotquad.app's flag doesn't say it twice.
    public static func publicAlert(
        old: LiteMe?,
        new: LiteMe,
        ipChanges: Bool = true,
        vpnChanges: Bool = true,
        vpnAnnounced: Bool = false
    ) -> IPAlert? {
        guard let old, old.ip != new.ip || old.vpn != new.vpn else { return nil }
        let details = [LiteText.shortPlace(new), new.owner].compactMap { $0 }.joined(separator: " · ")
        let move = old.ip == new.ip ? new.ip : "\(old.ip) → \(new.ip)"
        let body = details.isEmpty ? move : "\(move)\n\(details)"

        if vpnChanges, !vpnAnnounced, old.vpn == true, new.vpn == false { return .vpnOff(body) }
        if vpnChanges, !vpnAnnounced, old.vpn != true, new.vpn == true { return .vpnOn(body) }
        guard ipChanges, old.ip != new.ip else { return nil }
        return IPAlert(kind: .publicIP, title: "Public IP changed", body: body, symbol: "network", short: "New IP")
    }

    /// The alert for the Mac starting or stopping sending everything through
    /// a tunnel, or nil. Read from the Mac, so it needs no lookup, and it
    /// works for a VPN dotquad.app doesn't know, such as one you run yourself.
    /// `old` is the last network the Mac was online with.
    public static func tunnelAlert(old: LocalNetwork?, new: LocalNetwork?) -> IPAlert? {
        guard let old, let new, old.isTunnel != new.isTunnel else { return nil }
        if new.isTunnel {
            return .vpnOn("Everything goes through \(new.interface) now.")
        }
        let back = [new.kind, new.address].compactMap { $0 }.joined(separator: " · ")
        return .vpnOff(back.isEmpty ? "Traffic no longer goes through the VPN." : "Back on \(back)")
    }

    /// Whether the Mac moved to another network: another interface, address
    /// or router, a VPN connecting or dropping, or switching servers. The
    /// public IP may have changed with it, so it's worth asking again. A
    /// change of DNS servers alone isn't a move.
    public static func moved(from old: LocalNetwork, to new: LocalNetwork) -> Bool {
        old.interface != new.interface || old.ipv4 != new.ipv4 || old.ipv6 != new.ipv6 || old.router != new.router
    }

    /// The VPN alert with the public IP dotquad.app saw before and after,
    /// once the new answer is in. Unchanged when there's no new answer.
    public static func withPublic(_ alert: IPAlert, before: LiteMe?, after: LiteMe?) -> IPAlert {
        guard let after else { return alert }
        let line: String
        if let before, before.ip == after.ip {
            line = "Public IP still \(after.ip)"
        } else if let before {
            line = "\(before.ip) → \(after.ip)"
        } else {
            line = "Public IP \(after.ip)"
        }
        let details = [LiteText.shortPlace(after), after.owner].compactMap { $0 }.joined(separator: " · ")
        return IPAlert(
            kind: alert.kind,
            title: alert.title,
            body: details.isEmpty ? line : "\(line)\n\(details)",
            symbol: alert.symbol,
            short: alert.short,
            isWarning: alert.isWarning
        )
    }

    /// The alert for a new local address, or nil. Going offline, coming back
    /// with the same address, or a VPN's tunnel taking over isn't a change:
    /// the tunnel has its own alert.
    public static func localAlert(old: LocalNetwork?, new: LocalNetwork?) -> IPAlert? {
        guard let old, !old.isTunnel, let before = old.address,
              let new, !new.isTunnel, let after = new.address, before != after else { return nil }
        let place = new.kind ?? new.interface
        return IPAlert(
            kind: .localIP,
            title: "Local IP changed",
            body: "\(before) → \(after)\n\(place)" + (new.router.map { " · router \($0)" } ?? ""),
            symbol: new.symbol,
            short: "New local IP"
        )
    }

    /// What the test button shows, so the user can see alerts work.
    public static let test = IPAlert(
        kind: .publicIP,
        title: "Dotquad Lite alerts work",
        body: "This is how a change of IP or VPN shows.",
        symbol: "checkmark.circle",
        short: "Test"
    )
}
