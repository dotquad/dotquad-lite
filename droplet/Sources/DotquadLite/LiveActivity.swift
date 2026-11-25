//
//  LiveActivity.swift
//  DotquadLite
//
//  A live activity in the island, for two things, each with its own switch,
//  off until the user turns it on:
//
//  - While the VPN is on: a shield in one wing, where the public IP appears
//    (flag and country code) in the other.
//  - While the internet is out: an amber Wi-Fi warning and "No internet",
//    "Offline" or "Sign in". It comes first, since it's the one to act on.
//
//  Clicking it opens the shelf on the My IP widget.
//
//  The VPN counts as on when the Mac sends everything through a tunnel (read
//  from the Mac, nothing sent), or, with lookups on, when dotquad.app flags the
//  public IP as a VPN's. It's a connection the user chose, so it's in the
//  `status` band: below Droppy's own activities, timers and downloads.
//

import SwiftUI
import Combine
import DroppyKit

extension DotquadLiteDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {
        host?.log.notice("live activity seat: \(seat)")
        switch seat {
        case .compact: activitySeat = "compact"
        case .secondary: activitySeat = "secondary"
        case .none(let reason): activitySeat = reason.rawValue
        @unknown default: activitySeat = "unknown"
        }
    }

    public func makeCompactLeading(context: CompactLiveActivityContext) -> AnyView {
        AnyView(ActivityGlyph(droplet: self))
    }

    public func makeCompactTrailing(context: CompactLiveActivityContext) -> AnyView {
        AnyView(ActivityText(droplet: self))
    }

    public func makeCompactLeading() -> AnyView { AnyView(ActivityGlyph(droplet: self)) }

    public func makeCompactTrailing() -> AnyView { AnyView(ActivityText(droplet: self)) }

    /// Not mounted by Droppy: hovering or clicking the row opens the shelf.
    public func makeExpanded(context: LiveActivityContext) -> AnyView { AnyView(EmptyView()) }

    /// The round pill beside one of Droppy's own activities, when the user
    /// allows it in Droppy's settings: the shield alone.
    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        AnyView(ActivityGlyph(droplet: self))
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? { nil }

    // MARK: State

    /// Whether the VPN is on, as far as Dotquad Lite can tell.
    var vpnIsOn: Bool {
        if localNetwork?.isTunnel == true { return true }
        return lookupsOn && result?.vpn == true
    }

    /// What the activity is about now: No internet comes first, since it's
    /// the one to act on; the VPN otherwise.
    var activityTopic: ActivityTopic? {
        if internetActivityOn, let connectivity, connectivity.isOut { return .internet(connectivity) }
        if activityOn, vpnIsOn { return .vpn }
        return nil
    }

    /// Publishes the activity for the topic, or nil. The state stays the same
    /// while a topic is up: what changes (the place, the time out) is drawn by
    /// the views, so the row never re-arbitrates.
    func updateActivity() {
        // The lock screen row says the same things, so it follows along.
        updateLockScreen()
        let state: LiveActivityState?
        switch activityTopic {
        case .vpn?:
            state = LiveActivityState(
                priority: .status,
                accessibilityTitle: "VPN on",
                accessibilityValue: { [weak self] in self?.activityPlaceText ?? "" },
                joinsPersistentActivitySet: true,
                compactPresentation: CompactLiveActivityPresentationMetadata(
                    id: "vpn",
                    accessibilityLabel: "VPN on",
                    accessibilityValue: ""
                ),
                expandedWidgetID: "my-ip"
            )
        case .internet(let connectivity)?:
            let title = ActivityTopic.internetTitle(connectivity)
            // Something to act on, so `attention`. The time out changes
            // every minute, which keeps it from going stale.
            state = LiveActivityState(
                priority: .attention,
                accessibilityTitle: title,
                accessibilityValue: { [weak self] in
                    self?.outSince.map { "Out " + LiteText.outFor(Date().timeIntervalSince($0)) } ?? ""
                },
                joinsPersistentActivitySet: true,
                compactPresentation: CompactLiveActivityPresentationMetadata(
                    id: "internet-\(connectivity.rawValue)",
                    accessibilityLabel: title,
                    accessibilityValue: "",
                    preferredWidth: 84
                ),
                expandedWidgetID: "my-ip"
            )
        case nil:
            state = nil
        }
        guard activitySubject.value != state else { return }
        if state == nil { activitySeat = nil }
        activitySubject.send(state)
    }

    /// The trailing wing's words.
    var activityTrailingText: String {
        switch activityTopic {
        case .internet(let connectivity)?: return ActivityTopic.internetShort(connectivity)
        default: return activityPlaceText
        }
    }

    /// "🇳🇱 NL" where the public IP appears, or "VPN" before an answer.
    var activityPlaceText: String {
        guard lookupsOn, let result else { return "VPN" }
        let code = result.country.flatMap { $0.isEmpty ? nil : $0.uppercased() }
        switch (LiteText.flag(code), code) {
        case let (flag?, code?): return "\(flag) \(code)"
        case let (nil, code?): return code
        default: return "VPN"
        }
    }
}

/// What the live activity shows.
enum ActivityTopic: Equatable {
    case vpn
    case internet(Connectivity)

    static func internetTitle(_ connectivity: Connectivity) -> String {
        switch connectivity {
        case .offline: return "Offline"
        case .signIn: return "Sign in to this network"
        default: return "No internet"
        }
    }

    static func internetShort(_ connectivity: Connectivity) -> String {
        switch connectivity {
        case .offline: return "Offline"
        case .signIn: return "Sign in"
        default: return "No internet"
        }
    }
}

// MARK: - Views

/// The leading glyph: a teal shield for the VPN, an amber Wi-Fi warning
/// while the internet is out. No padding or frame: the host insets the wing.
private struct ActivityGlyph: View {
    @ObservedObject var droplet: DotquadLiteDroplet

    var body: some View {
        let symbol: String
        let tint: Color
        switch droplet.activityTopic {
        case .internet(.offline)?: (symbol, tint) = ("wifi.slash", LiteColor.flag)
        case .internet?: (symbol, tint) = ("wifi.exclamationmark", LiteColor.flag)
        default: (symbol, tint) = ("lock.shield.fill", LiteColor.signal)
        }
        return Image(systemName: symbol)
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
            .foregroundStyle(tint)
    }
}

/// The trailing words. Watches the Droplet, so a new answer redraws it
/// without publishing a new state.
private struct ActivityText: View {
    @ObservedObject var droplet: DotquadLiteDroplet

    var body: some View {
        Text(verbatim: droplet.activityTrailingText)
            .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .lineLimit(1)
    }
}
