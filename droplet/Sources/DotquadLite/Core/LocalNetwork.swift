//
//  LocalNetwork.swift
//  DotquadLite
//
//  This Mac's side of the network: the interface it's using, its local
//  addresses, the router and the DNS servers. Read from the Mac itself, so
//  nothing is sent and no consent is needed.
//
//  The primary interface, the router and the DNS servers come from the
//  System Configuration store (what System Settings, Network shows); the
//  addresses from getifaddrs.
//

import Foundation
import SystemConfiguration

/// The network this Mac is on, as the Mac sees it.
public struct LocalNetwork: Codable, Equatable, Sendable {
    /// The BSD name, for example "en0".
    public let interface: String
    /// What System Settings calls it, for example "Wi-Fi" or "Ethernet".
    public let kind: String?
    public let ipv4: String?
    /// A global IPv6 address, when the network gives one. Never link-local.
    public let ipv6: String?
    public let router: String?
    public let dns: [String]

    public init(interface: String, kind: String?, ipv4: String?, ipv6: String?, router: String?, dns: [String]) {
        self.interface = interface
        self.kind = kind
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.router = router
        self.dns = dns
    }

    /// The local address to show and copy: IPv4 first.
    public var address: String? { ipv4 ?? ipv6 }

    /// An SF Symbol for the interface.
    public var symbol: String {
        switch kind?.lowercased() {
        case let k? where k.contains("wi-fi") || k.contains("wifi") || k.contains("airport"): return "wifi"
        case let k? where k.contains("ethernet") || k.contains("thunderbolt") || k.contains("usb"): return "cable.connector"
        case let k? where k.contains("iphone"): return "iphone"
        default: return "network"
        }
    }

    /// "Wi-Fi · en0", or the BSD name alone.
    public var interfaceLabel: String {
        guard let kind, !kind.isEmpty else { return interface }
        return "\(kind) · \(interface)"
    }
}

// MARK: - Reading

public extension LocalNetwork {
    /// The network on the primary interface, or nil when the Mac is offline.
    static func read() -> LocalNetwork? {
        let store = SCDynamicStoreCreate(nil, "app.dotquad.lite" as CFString, nil, nil)
        let ipv4State = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) } as? [String: Any]
        let ipv6State = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv6" as CFString) } as? [String: Any]
        let dnsState = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/DNS" as CFString) } as? [String: Any]

        guard let primary = (ipv4State?["PrimaryInterface"] ?? ipv6State?["PrimaryInterface"]) as? String else {
            return nil
        }
        let addresses = interfaceAddresses()[primary] ?? []
        return LocalNetwork(
            interface: primary,
            kind: interfaceKinds()[primary],
            ipv4: pickIPv4(addresses),
            ipv6: pickIPv6(addresses),
            router: (ipv4State?["Router"] as? String) ?? (ipv6State?["Router"] as? String).flatMap(Self.usefulIPv6),
            dns: (dnsState?["ServerAddresses"] as? [String] ?? []).filter { !$0.isEmpty }
        )
    }

    /// Every interface's addresses, by BSD name, as strings.
    private static func interfaceAddresses() -> [String: [String]] {
        var result: [String: [String]] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let sa = entry.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            result[name, default: []].append(String(cString: host))
        }
        return result
    }

    /// "Wi-Fi", "Ethernet" and so on, by BSD name.
    private static func interfaceKinds() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: String] = [:]
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            if let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                result[bsd] = name
            }
        }
        return result
    }
}

// MARK: - Picking addresses

public extension LocalNetwork {
    /// The first usable IPv4 address: not loopback, not self-assigned.
    static func pickIPv4(_ addresses: [String]) -> String? {
        addresses.first { address in
            guard address.contains("."), !address.contains(":") else { return false }
            return !address.hasPrefix("127.") && !address.hasPrefix("169.254.")
        }
    }

    /// The first global IPv6 address, preferring a stable one over a
    /// temporary one when both are listed (getifaddrs lists the stable first).
    static func pickIPv6(_ addresses: [String]) -> String? {
        addresses.lazy.compactMap(usefulIPv6).first
    }

    /// The address without its zone, or nil for loopback, link-local and
    /// unique-local (fc00::/7) addresses, which say nothing outside the LAN.
    static func usefulIPv6(_ address: String) -> String? {
        guard address.contains(":") else { return nil }
        let bare = String(address.split(separator: "%", maxSplits: 1).first ?? "")
        let lower = bare.lowercased()
        if lower == "::1" || lower == "::" { return nil }
        if lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb") { return nil }
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return nil }
        return bare
    }
}
