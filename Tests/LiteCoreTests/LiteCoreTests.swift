import Foundation
import Testing
@testable import LiteCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let english = Locale(identifier: "en_US")

private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: LiteClient.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private let sample = LiteMe(
    ip: "203.0.113.7", city: "Amsterdam", country: "NL", asn: 9009,
    owner: "M247 Europe", vpn: true, hosting: true
)

@Suite struct Decoding {
    @Test func decodesTheLiveShape() throws {
        let body = #"{"ip":"135.148.94.69","city":"Torrance","country":"US","asn":16276,"owner":"OVH SAS","vpn":false,"hosting":true}"#
        let me = try LiteClient.parse(data: Data(body.utf8), response: response(200), now: now)
        #expect(me == LiteMe(ip: "135.148.94.69", city: "Torrance", country: "US", asn: 16276,
                             owner: "OVH SAS", vpn: false, hosting: true))
    }

    @Test func decodesNulls() throws {
        let body = #"{"ip":"2001:db8::1","city":null,"country":null,"asn":null,"owner":null,"vpn":null,"hosting":null}"#
        let me = try LiteClient.parse(data: Data(body.utf8), response: response(200), now: now)
        #expect(me.ip == "2001:db8::1")
        #expect(me.vpn == nil)
    }

    @Test func refusesABadBody() {
        #expect(throws: LiteError.badResponse) {
            try LiteClient.parse(data: Data("<html>".utf8), response: response(200), now: now)
        }
        #expect(throws: LiteError.badResponse) {
            try LiteClient.parse(data: Data(#"{"ip":""}"#.utf8), response: response(200), now: now)
        }
    }

    @Test func mapsOtherStatuses() {
        #expect(throws: LiteError.unavailable(status: 503)) {
            try LiteClient.parse(data: Data(), response: response(503), now: now)
        }
    }
}

@Suite struct RetryAfter {
    @Test func readsSeconds() {
        #expect(LiteClient.retryAfter("42", now: now) == 42)
    }

    @Test func readsAnHTTPDate() {
        let later = now.addingTimeInterval(120)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        #expect(LiteClient.retryAfter(formatter.string(from: later), now: now) == 120)
    }

    @Test func fallsBackAndClamps() {
        #expect(LiteClient.retryAfter(nil, now: now) == 60)
        #expect(LiteClient.retryAfter("soon", now: now) == 60)
        #expect(LiteClient.retryAfter("0", now: now) == 1)
        #expect(LiteClient.retryAfter("-5", now: now) == 1)
        #expect(LiteClient.retryAfter("999999", now: now) == 3600)
    }

    @Test func a429CarriesTheWait() {
        #expect(throws: LiteError.rateLimited(retryAfter: 30)) {
            try LiteClient.parse(data: Data(), response: response(429, headers: ["Retry-After": "30"]), now: now)
        }
    }
}

@Suite struct Policy {
    @Test func firstFetchIsAllowed() {
        #expect(RefreshPolicy().mayFetch(now: now))
    }

    @Test func atMostOnceEveryFiveMinutes() {
        var policy = RefreshPolicy()
        policy.didAttempt(at: now)
        #expect(!policy.mayFetch(now: now.addingTimeInterval(299)))
        #expect(policy.mayFetch(now: now.addingTimeInterval(300)))
    }

    @Test func aNetworkChangeAllowsOneMore() {
        var policy = RefreshPolicy()
        policy.didAttempt(at: now)
        policy.networkDidChange()
        #expect(policy.mayFetch(now: now.addingTimeInterval(10)))
        #expect(!policy.isFresh(now, now: now.addingTimeInterval(10)))
        policy.didAttempt(at: now.addingTimeInterval(10))
        #expect(!policy.mayFetch(now: now.addingTimeInterval(20)))
    }

    @Test func retryAfterBlocksEvenANetworkChange() {
        var policy = RefreshPolicy()
        policy.didAttempt(at: now)
        policy.didRateLimit(retryAfter: 600, now: now)
        policy.networkDidChange()
        #expect(!policy.mayFetch(now: now.addingTimeInterval(599)))
        #expect(policy.blockedFor(now: now.addingTimeInterval(500)) == 100)
        #expect(policy.mayFetch(now: now.addingTimeInterval(600)))
        #expect(policy.blockedFor(now: now.addingTimeInterval(600)) == nil)
    }

    @Test func freshness() {
        let policy = RefreshPolicy()
        #expect(policy.isFresh(now, now: now.addingTimeInterval(299)))
        #expect(!policy.isFresh(now, now: now.addingTimeInterval(300)))
        #expect(!policy.isFresh(nil, now: now))
    }

    @Test func jitterStaysInRange() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<1000 {
            let wait = RefreshPolicy.jitter(using: &generator)
            #expect(wait >= 0 && wait <= 30)
        }
    }
}

@Suite struct Text {
    @Test func location() {
        #expect(LiteText.location(sample, locale: english) == "Appears in Amsterdam, Netherlands")
        let noCity = LiteMe(ip: "x", city: nil, country: "NL", asn: nil, owner: nil, vpn: nil, hosting: nil)
        #expect(LiteText.location(noCity, locale: english) == "Appears in Netherlands")
        let nothing = LiteMe(ip: "x", city: nil, country: nil, asn: nil, owner: nil, vpn: nil, hosting: nil)
        #expect(LiteText.location(nothing, locale: english) == nil)
    }

    @Test func networkAndBadge() {
        #expect(LiteText.network(sample) == "M247 Europe · AS9009")
        #expect(LiteText.badge(sample) == .vpn)
        let hosting = LiteMe(ip: "x", city: nil, country: nil, asn: 16276, owner: nil, vpn: false, hosting: true)
        #expect(LiteText.network(hosting) == "AS16276")
        #expect(LiteText.badge(hosting) == .hosting)
        #expect(LiteText.vpnStatus(hosting) == "No VPN")
    }

    @Test func updatedAgo() {
        #expect(LiteText.updated(since: now, now: now.addingTimeInterval(30)) == "Updated just now")
        #expect(LiteText.updated(since: now, now: now.addingTimeInterval(12 * 60)) == "Updated 12 min ago")
        #expect(LiteText.updated(since: now, now: now.addingTimeInterval(3 * 3600)) == "Updated 3 hr ago")
        #expect(LiteText.updated(since: now, now: now.addingTimeInterval(26 * 3600)) == "Updated 1 day ago")
    }

    @Test func rateLimitMessageRoundsUp() {
        #expect(LiteError.rateLimited(retryAfter: 61).message == "dotquad.app is busy. Dotquad Lite tries again in 2 min.")
    }
}

@Suite struct HandOffLinks {
    @Test func ipLookup() {
        #expect(HandOff.ipLookup("203.0.113.7")?.absoluteString == "https://dotquad.app/?ip=203.0.113.7&from=lite")
        #expect(HandOff.ipLookup("2001:db8::1")?.absoluteString == "https://dotquad.app/?ip=2001:db8::1&from=lite")
        #expect(HandOff.ipLookup("not an ip") == nil)
    }

    @Test func lookupPicksTheTool() {
        #expect(HandOff.lookup(" 1.1.1.1 ")?.absoluteString == "https://dotquad.app/?ip=1.1.1.1&from=lite")
        #expect(HandOff.lookup("https://Example.com/a")?.absoluteString == "https://dotquad.app/dns/?q=example.com&from=lite")
        #expect(HandOff.lookup("hello") == nil)
    }

    @Test func gradeAndLinkCheck() {
        #expect(HandOff.grade("github.com.")?.absoluteString == "https://dotquad.app/check/github.com?from=lite")
        #expect(HandOff.grade("../etc") == nil)
        #expect(HandOff.linkCheck("https://x.example/?a=1&b=2")?.absoluteString
            == "https://dotquad.app/link-check/?q=https://x.example/?a%3D1%26b%3D2&from=lite")
        #expect(HandOff.linkCheck("two words") == nil)
    }

    @Test func domains() {
        #expect(HandOff.domain("sub.Example.co.uk") == "sub.example.co.uk")
        #expect(HandOff.domain("-bad.com") == nil)
        #expect(HandOff.domain("a..com") == nil)
        #expect(HandOff.domain("10.0.0.1") == nil)
        #expect(HandOff.domain("ex ample.com") == nil)
    }
}

@Suite struct LocalAddresses {
    @Test func picksAUsableIPv4() {
        #expect(LocalNetwork.pickIPv4(["fe80::1%en0", "169.254.3.4", "192.168.1.23"]) == "192.168.1.23")
        #expect(LocalNetwork.pickIPv4(["127.0.0.1", "169.254.3.4"]) == nil)
    }

    @Test func picksAGlobalIPv6() {
        #expect(LocalNetwork.pickIPv6(["192.168.1.23", "fe80::1c2b%en0", "fd12::5", "2001:db8::42"]) == "2001:db8::42")
        #expect(LocalNetwork.pickIPv6(["fe80::1%en0", "::1"]) == nil)
        #expect(LocalNetwork.usefulIPv6("2001:db8::1%en0") == "2001:db8::1")
    }

    @Test func labelsAndSymbols() {
        let wifi = LocalNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "10.0.0.5", ipv6: nil, router: "10.0.0.1", dns: [])
        #expect(wifi.interfaceLabel == "Wi-Fi · en0")
        #expect(wifi.symbol == "wifi")
        #expect(wifi.address == "10.0.0.5")
        let wired = LocalNetwork(interface: "en7", kind: nil, ipv4: nil, ipv6: "2001:db8::9", router: nil, dns: [])
        #expect(wired.interfaceLabel == "en7")
        #expect(wired.symbol == "network")
        #expect(wired.address == "2001:db8::9")
    }

    @Test func readsThisMacWithoutCrashing() {
        // Offline in CI is fine; online it must name an interface.
        if let local = LocalNetwork.read() {
            #expect(!local.interface.isEmpty)
        }
    }
}

@Suite struct WidgetText {
    @Test func flags() {
        #expect(LiteText.flag("nl") == "🇳🇱")
        #expect(LiteText.flag("US") == "🇺🇸")
        #expect(LiteText.flag("USA") == nil)
        #expect(LiteText.flag("1A") == nil)
        #expect(LiteText.flag(nil) == nil)
    }

    @Test func placesAndChips() {
        #expect(LiteText.place(sample, locale: english) == "Amsterdam, Netherlands")
        #expect(LiteText.chip(sample) == "VPN")
        let plain = LiteMe(ip: "1.2.3.4", city: nil, country: "DE", asn: nil, owner: nil, vpn: false, hosting: false)
        #expect(LiteText.place(plain, locale: english) == "Germany")
        #expect(LiteText.chip(plain) == "No VPN")
        let loading = LiteMe(ip: "1.2.3.4", city: nil, country: nil, asn: nil, owner: nil, vpn: nil, hosting: nil)
        #expect(LiteText.chip(loading) == "Checking")
    }

    @Test func dns() {
        #expect(LiteText.dnsSummary([]) == nil)
        #expect(LiteText.dnsSummary(["1.1.1.1"]) == "1.1.1.1")
        #expect(LiteText.dnsSummary(["1.1.1.1", "8.8.8.8", "9.9.9.9"]) == "1.1.1.1 +2")
    }
}

@Suite struct Map {
    @Test func gridIsWhole() {
        #expect(WorldDots.rows.count == 40)
        #expect(WorldDots.rows.allSatisfy { $0.utf8.count == WorldDots.columns })
    }

    @Test func landWhereItShouldBe() {
        func land(_ latitude: Double, _ longitude: Double) -> Bool {
            let p = WorldDots.point(latitude: latitude, longitude: longitude)!
            let column = min(Int(p.x * Double(WorldDots.columns)), WorldDots.columns - 1)
            let row = min(Int(p.y * Double(WorldDots.rows.count)), WorldDots.rows.count - 1)
            return WorldDots.isLand(column: column, row: row)
        }
        #expect(land(39.0, -98.0))     // Kansas
        #expect(land(-15.0, -55.0))    // Brazil
        #expect(land(25.0, 20.0))      // Sahara
        #expect(!land(30.0, -40.0))    // mid-Atlantic
        #expect(!land(-30.0, -120.0))  // South Pacific
    }

    @Test func pointsClampAndRefuse() {
        let north = WorldDots.point(latitude: 89, longitude: 0)!
        #expect(north.y == 0)
        #expect(WorldDots.point(latitude: 91, longitude: 0) == nil)
        #expect(WorldDots.point(latitude: 0, longitude: 181) == nil)
    }

    @Test func decodesCoordinatesAndTheirAbsence() throws {
        let with = #"{"ip":"1.2.3.4","city":"Torrance","country":"US","asn":1,"owner":"x","vpn":false,"hosting":true,"latitude":33.8,"longitude":-118.3}"#
        let me = try JSONDecoder().decode(LiteMe.self, from: Data(with.utf8))
        #expect(me.latitude == 33.8 && me.longitude == -118.3)
        let without = #"{"ip":"1.2.3.4","city":null,"country":"US","asn":1,"owner":"x","vpn":false,"hosting":true}"#
        #expect(try JSONDecoder().decode(LiteMe.self, from: Data(without.utf8)).latitude == nil)
    }
}

@Suite struct ShortPlaces {
    @Test func shortens() {
        #expect(LiteText.shortPlace(sample) == "Amsterdam, NL")
        let noCity = LiteMe(ip: "1.2.3.4", city: nil, country: "DE", asn: nil, owner: nil, vpn: nil, hosting: nil)
        #expect(LiteText.shortPlace(noCity) == LiteText.countryName("DE"))
    }
}

@Suite struct Alerts {
    private func me(_ ip: String, vpn: Bool?) -> LiteMe {
        LiteMe(ip: ip, city: "Amsterdam", country: "NL", asn: 9009, owner: "M247 Europe", vpn: vpn, hosting: vpn)
    }

    @Test func firstAnswerIsNotAChange() {
        #expect(IPChange.publicAlert(old: nil, new: me("1.1.1.1", vpn: false)) == nil)
        #expect(IPChange.publicAlert(old: me("1.1.1.1", vpn: false), new: me("1.1.1.1", vpn: false)) == nil)
    }

    @Test func publicChange() {
        let alert = IPChange.publicAlert(old: me("1.1.1.1", vpn: false), new: me("2.2.2.2", vpn: false))
        #expect(alert?.title == "Public IP changed")
        #expect(alert?.body == "1.1.1.1 → 2.2.2.2\nAmsterdam, NL · M247 Europe")
        #expect(alert?.kind == .publicIP)
    }

    @Test func vpnOffAndOn() {
        #expect(IPChange.publicAlert(old: me("1.1.1.1", vpn: true), new: me("2.2.2.2", vpn: false))?.title == "VPN is off")
        #expect(IPChange.publicAlert(old: me("1.1.1.1", vpn: false), new: me("2.2.2.2", vpn: true))?.title == "VPN is on")
        // Lists finishing loading on the same address isn't news.
        #expect(IPChange.publicAlert(old: me("1.1.1.1", vpn: nil), new: me("1.1.1.1", vpn: false)) == nil)
    }

    @Test func localChange() {
        let a = LocalNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "192.168.1.5", ipv6: nil, router: "192.168.1.1", dns: [])
        let b = LocalNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "10.0.0.7", ipv6: nil, router: "10.0.0.1", dns: [])
        let alert = IPChange.localAlert(old: a, new: b)
        #expect(alert?.title == "Local IP changed")
        #expect(alert?.body == "192.168.1.5 → 10.0.0.7\nWi-Fi · router 10.0.0.1")
        #expect(IPChange.localAlert(old: a, new: a) == nil)
        #expect(IPChange.localAlert(old: a, new: nil) == nil)
        #expect(IPChange.localAlert(old: nil, new: b) == nil)
    }
}
