//
//  HandOff.swift
//  DotquadLite
//
//  Links to the website tools. Lite shows nothing about other addresses or
//  domains itself: it opens dotquad.app with the input filled in.
//

import Foundation

public enum HandOff {
    public static let site = URL(string: "https://dotquad.app")!
    /// Added to every link so the site can say "Opened from Dotquad Lite".
    /// The site doesn't log it.
    static let fromItem = URLQueryItem(name: "from", value: "lite")

    /// The home page.
    public static var home: URL { url("/", []) }

    /// The IP lookup on the home page, for this Mac's own address.
    public static func ipLookup(_ ip: String) -> URL? {
        guard isIPAddress(ip) else { return nil }
        return url("/", [URLQueryItem(name: "ip", value: ip)])
    }

    /// An IP opens the IP lookup; a domain opens the DNS lookup.
    public static func lookup(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isIPAddress(text) { return ipLookup(text) }
        guard let domain = domain(text) else { return nil }
        return url("/dns/", [URLQueryItem(name: "q", value: domain)])
    }

    /// The domain report card: `/check/{domain}`.
    public static func grade(_ input: String) -> URL? {
        guard let domain = domain(input) else { return nil }
        return url("/check/\(domain)", [])
    }

    /// The link checker. The page reads the link from `q`.
    public static func linkCheck(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2048, !text.contains(where: \.isWhitespace) else { return nil }
        return url("/link-check/", [URLQueryItem(name: "q", value: text)])
    }

    public static var checkup: URL { url("/checkup/", []) }
    public static var vpnTest: URL { url("/vpn-test/", []) }

    // MARK: Input

    /// IPv4 or IPv6, as the system parses it.
    public static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return text.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    /// A hostname from what someone typed or pasted: "Example.com",
    /// "https://example.com/path" and "example.com." all give "example.com".
    /// Nil for anything that isn't a plausible domain.
    public static func domain(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.contains("://"), let host = URL(string: text)?.host {
            text = host
        }
        if text.hasSuffix(".") { text.removeLast() }
        guard text.count <= 253, text.contains("."), !isIPAddress(text) else { return nil }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard (1...63).contains(label.count),
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return nil }
        }
        return text
    }

    private static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var parts = URLComponents(url: site, resolvingAgainstBaseURL: false)!
        parts.path = path
        parts.queryItems = items + [fromItem]
        return parts.url!
    }
}
