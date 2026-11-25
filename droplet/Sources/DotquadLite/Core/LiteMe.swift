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
        "After each network change Dotquad Lite asks dotquad.app, even with the widget closed."

    public static let vpnAlertNote =
        "When your Mac starts or stops sending everything through a VPN, or dotquad.app sees your public IP become a VPN's or stop being one. After each network change Dotquad Lite asks dotquad.app, even with the widget closed."

    public static let vpnAlertLocalNote =
        "When your Mac starts or stops sending everything through a VPN. Read from this Mac; nothing is sent. Turn on \"Look up my public IP\" to also catch VPNs dotquad.app recognizes."

    public static let localAlertNote =
        "Read from this Mac; nothing is sent."

    public static let activityNote =
        "While your VPN is on, a shield and the country your IP appears in stay in the island, like Now Playing. Click it to open My IP. Read from this Mac; with \"Look up my public IP\" on, it also shows VPNs dotquad.app recognizes."

    /// What Settings says about the VPN live activity. `seat` is what Droppy
    /// last said: "compact", "secondary", a reason it isn't showing, or nil.
    public static func activityStatus(active: Bool, published: Bool, seat: String?) -> String {
        guard active else {
            return "Nothing to show right now. It appears while your VPN is on, or while the internet is out, for the ones turned on above."
        }
        guard published else { return "Turning the activity on now." }
        switch seat {
        case "compact"?: return "Showing in the island."
        case "secondary"?: return "Showing in the pill beside Droppy's own activity."
        case "surfaceSuppressed"?, "surface-suppressed"?:
            return "Waiting: Droppy has the island for something else (music, a timer, a HUD, a meeting or the open shelf). It comes back when that's done, or turn on Show beside Droppy's activities."
        case "outranked"?: return "Waiting: another Droplet's activity has the island."
        case "display-ineligible"?: return "Waiting: Droppy doesn't show activities on this display. Check Live Activities, Show activities on, in Droppy Settings."
        case "user-disabled"?: return "Droppy has live activities turned off for Dotquad Lite."
        case "idle"?: return "Not showing."
        case "duplicatesBuiltIn"?, "duplicates-built-in"?: return "Waiting: one of Droppy's own activities is showing."
        case let reason?: return "Droppy isn't showing it (\(reason))."
        case nil: return "Droppy hasn't answered yet; close the shelf to see it."
        }
    }

    public static let lookUpNote =
        "Add the Look Up widget to Droppy's shelf: type an IP, a domain or a link, and it opens the right tool on dotquad.app. It also has the network checkup and the VPN test. Press ⌃⌥D from anywhere to open it, or set your own shortcut."

    public static let lockScreenNote =
        "A row on Droppy's lock screen: VPN on or No VPN and the country your IP appears in, or No internet when it's out. Your IP stays off it unless you turn it on below."

    public static let lockScreenIPNote =
        "Shows your public IP on the lock screen instead of the country. Anyone who can see your screen can read it. Needs \"Look up my public IP\"."

    public static let internetAlertNote =
        "When Wi-Fi or Ethernet is connected but nothing loads, or a network wants you to sign in, and Back online when it works again. To check, Dotquad Lite asks captive.apple.com, the page macOS itself asks, after network changes and every 2 minutes; nothing about you is sent. For a Mac that's fully offline, turn on No internet in Droppy's Live Activities settings."

    public static let internetActivityNote =
        "While the internet is out, a Wi-Fi warning stays in the island until it's back, ahead of the VPN. Checks captive.apple.com, like the alert."

    /// Under the "Show alerts as" choice: what the two are, in Droppy's words.
    public static let alertStyleNote =
        "A HUD shows in the island for a few seconds, like Caps Lock, then goes. A notification waits in Droppy's banners until you see it, and follows Focus and Show notifications. If the one you pick can't show, Dotquad Lite uses the other."

    /// Why a notification didn't show: "not-granted" or "refused".
    public static func notificationIssue(_ issue: String) -> String {
        issue == "not-granted"
            ? "Notifications: Droppy hasn't given Dotquad Lite permission to post them. Turn it on in this Droplet's permissions above."
            : "Notifications: Droppy has permission on but said no. Its Show notifications switch for Dotquad Lite may be off, a Focus may be on, or Silence during Focus may be holding banners."
    }

    /// Why a HUD didn't show: "not-granted" or "refused".
    public static func hudIssue(_ issue: String) -> String {
        issue == "not-granted"
            ? "HUD: Droppy hasn't given Dotquad Lite permission to show one. Turn it on in this Droplet's permissions above."
            : "HUD: Droppy said no. Close the shelf and try again."
    }

    /// What Settings says about the last alert: "hud", "notification" or "refused",
    /// and whether it went where the user chose.
    public static func alertOutcome(_ outcome: String, asChosen: Bool) -> String {
        switch outcome {
        case "hud":
            return asChosen ? "Shown as a HUD in the island." : "Shown as a HUD, because Droppy didn't take the notification."
        case "notification":
            return asChosen ? "Shown as a notification." : "Shown as a notification, because the island was busy or the shelf was open."
        default:
            return "Droppy didn't show it. Check that HUDs and notifications are allowed for Dotquad Lite in its permissions above, that Show notifications is on, and that no Focus is on. Close the shelf and try again."
        }
    }

    public static let privacyNote =
        "Dotquad Lite asks dotquad.app only while the widget or tile is on screen, after a network change when public IP or VPN alerts are on, or when an AI app you allowed in Droppy asks. Your local IP, router and DNS servers are read from this Mac and never sent. With a No internet switch on, it asks captive.apple.com, the page macOS uses, whether the internet works; that sends nothing about you. Nothing about you is stored, on this Mac or on the server, beyond a count of requests."

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
