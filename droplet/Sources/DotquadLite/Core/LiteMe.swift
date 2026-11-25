//
//  LiteMe.swift
//  DotquadLite
//
//  The answer from `GET https://api.dotquad.app/lite/me`, and the text the
//  widget, the Command Center tile and the MCP tools show for it.
//
//  Nothing in Core imports DroppyKit, so the tests build it on its own.
//

import Foundation

/// This Mac's public IP as Dotquad sees it. The API's fields, unchanged.
public struct LiteMe: Codable, Equatable, Sendable {
    public let ip: String
    /// Missing when the data has no city for this address.
    public let city: String?
    /// ISO 3166-1 alpha-2 code, for example "NL".
    public let country: String?
    public let asn: Int?
    /// The network's owner, for example "M247 Europe".
    public let owner: String?
    /// Null while the API's privacy lists are loading.
    public let vpn: Bool?
    public let hosting: Bool?
    /// Where the data places the address, to 0.1°. Missing from older servers,
    /// and when the data has no city.
    public let latitude: Double?
    public let longitude: Double?

    public init(
        ip: String,
        city: String?,
        country: String?,
        asn: Int?,
        owner: String?,
        vpn: Bool?,
        hosting: Bool?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.ip = ip
        self.city = city
        self.country = country
        self.asn = asn
        self.owner = owner
        self.vpn = vpn
        self.hosting = hosting
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// What privacy detection says about the address, for the badge and the VPN dot.
public enum LiteBadge: String, Equatable, Sendable {
    case vpn = "VPN"
    case hosting = "Hosting"
}

/// The words Dotquad Lite shows. Kept here so the widget, the tile and the
/// tools say the same thing, and so the tests can check it.
public enum LiteText {
    public static let consentNotice =
        "Dotquad Lite sends your public IP to dotquad.app to look up its location and network."

    public static let locationTooltip =
        "Based on Dotquad's IP data. Other sites may see a different location."

    public static let publicAlertNote =
        "A banner when your public IP changes. After each network change Dotquad Lite asks dotquad.app, even with the widget closed."

    public static let vpnAlertNote =
        "A banner when your VPN turns on or off, as dotquad.app sees your public IP. After each network change Dotquad Lite asks dotquad.app, even with the widget closed."

    public static let localAlertNote =
        "A banner when your Mac's local IP changes. Read from this Mac; nothing is sent."

    public static let privacyNote =
        "Dotquad Lite asks dotquad.app only while the widget or tile is on screen, after a network change when public IP or VPN alerts are on, or when an AI app you allowed in Droppy asks. Your local IP, router and DNS servers are read from this Mac and never sent. Nothing about you is stored, on this Mac or on the server, beyond a count of requests."

    /// "Netherlands" for "NL", in the Mac's language. Falls back to the code.
    public static func countryName(_ code: String?, locale: Locale = .current) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return locale.localizedString(forRegionCode: code) ?? code
    }

    /// The flag emoji for an ISO 3166-1 alpha-2 code, "🇳🇱" for "NL".
    /// Nil for anything that isn't two letters A to Z.
    public static func flag(_ code: String?) -> String? {
        guard let code, code.count == 2 else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in code.uppercased().unicodeScalars {
            guard ("A"..."Z").contains(scalar),
                  let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - 0x41) else { return nil }
            scalars.append(indicator)
        }
        return String(scalars)
    }

    /// "Amsterdam, Netherlands", "Netherlands" or "Amsterdam". Nil when the
    /// data has neither.
    public static func place(_ me: LiteMe, locale: Locale = .current) -> String? {
        let country = countryName(me.country, locale: locale)
        let city = me.city.flatMap { $0.isEmpty ? nil : $0 }
        switch (city, country) {
        case let (city?, country?): return "\(city), \(country)"
        case let (nil, country?): return country
        case let (city?, nil): return city
        case (nil, nil): return nil
        }
    }

    /// "1.1.1.1", "1.1.1.1 +1". Nil for none.
    public static func dnsSummary(_ servers: [String]) -> String? {
        guard let first = servers.first else { return nil }
        return servers.count == 1 ? first : "\(first) +\(servers.count - 1)"
    }

    /// "Amsterdam, NL": the city and the country's code, for tight spaces.
    public static func shortPlace(_ me: LiteMe) -> String? {
        let city = me.city.flatMap { $0.isEmpty ? nil : $0 }
        let code = me.country.flatMap { $0.isEmpty ? nil : $0.uppercased() }
        switch (city, code) {
        case let (city?, code?): return "\(city), \(code)"
        case let (city?, nil): return city
        case (nil, _): return countryName(me.country)
        }
    }

    /// The status chip: "VPN", "Hosting", "No VPN", or "Checking" while the
    /// API's lists load.
    public static func chip(_ me: LiteMe) -> String {
        if let badge = badge(me) { return badge.rawValue }
        return me.vpn == nil ? "Checking" : "No VPN"
    }

    /// "Appears in Amsterdam, Netherlands", or "Appears in Netherlands" when
    /// the data has no city. Nil when it has neither.
    public static func location(_ me: LiteMe, locale: Locale = .current) -> String? {
        let country = countryName(me.country, locale: locale)
        let city = me.city.flatMap { $0.isEmpty ? nil : $0 }
        switch (city, country) {
        case let (city?, country?): return "Appears in \(city), \(country)"
        case let (nil, country?): return "Appears in \(country)"
        case let (city?, nil): return "Appears in \(city)"
        case (nil, nil): return nil
        }
    }

    /// "M247 Europe · AS9009". Either half alone when the other is missing.
    public static func network(_ me: LiteMe) -> String? {
        let parts = [me.owner.flatMap { $0.isEmpty ? nil : $0 }, me.asn.map { "AS\($0)" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VPN wins over hosting: a VPN exit usually sits in a hosting range too.
    public static func badge(_ me: LiteMe) -> LiteBadge? {
        if me.vpn == true { return .vpn }
        if me.hosting == true { return .hosting }
        return nil
    }

    /// "VPN", "No VPN", or "VPN status unknown" while the API's lists load.
    public static func vpnStatus(_ me: LiteMe) -> String {
        switch me.vpn {
        case true?: return "VPN"
        case false?: return "No VPN"
        case nil: return "VPN status unknown"
        }
    }

    /// "Updated just now", "Updated 12 min ago", "Updated 3 hr ago".
    public static func updated(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours) hr ago" }
        let days = hours / 24
        return "Updated \(days) day\(days == 1 ? "" : "s") ago"
    }
}
