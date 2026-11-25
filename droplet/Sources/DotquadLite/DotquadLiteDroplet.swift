//
//  DotquadLiteDroplet.swift
//  DotquadLite
//
//  Shows this Mac's public IP, where it appears to be, its network and
//  whether it's a VPN, and hands every other job to dotquad.app.
//
//  Nothing goes out until the user turns lookups on. After that a request
//  goes out only while the widget or the Command Center tile is on screen,
//  at most once every 5 minutes, plus once after the network changes.
//  Answers live in memory only.
//

import SwiftUI
import Combine
import Network
import DroppyKit

// MARK: - Principal

@objc(DotquadLitePrincipal)
public final class DotquadLitePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { DotquadLiteDroplet() }
}

// MARK: - Droplet

@MainActor
public final class DotquadLiteDroplet: NSObject, ObservableObject, Droplet, HUDPresenting {
    public nonisolated static let id: DropletID = "dotquad-lite"
    /// Sent as `User-Agent: DotquadLite/<version>`. Keep it equal to droplet.json.
    public nonisolated static let version = "1.0.0"

    static let lookupsOnKey = "lookupsOn"
    static let alertPublicKey = "alertPublicIPChange"
    static let alertLocalKey = "alertLocalIPChange"
    static let alertVPNKey = "alertVPNChange"
    static let alertStyleKey = "alertStyle"
    static let activityKey = "vpnActivity"
    static let alertInternetKey = "alertNoInternet"
    static let internetActivityKey = "internetActivity"
    static let lockScreenKey = "lockScreen"
    static let lockScreenIPKey = "lockScreenIP"

    private(set) var host: DropletHost?
    private let client = LiteClient(version: DotquadLiteDroplet.version)
    private var policy = RefreshPolicy()
    private var inFlight: Task<LiteMe, Error>?
    private var networkTask: Task<Void, Never>?
    /// The check after the Mac moved to another network or VPN.
    private var moveTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var hasSeenPath = false
    /// Whether the Mac has a network at all, from the path monitor.
    var pathSatisfied = true
    /// Whether the internet works, when one of the No internet switches is
    /// on. Nil when neither is, or before the first check.
    @Published var connectivity: Connectivity?
    /// When the internet went out, for "Back online" and the activity.
    var outSince: Date?
    /// The check loop: every 2 minutes while online, every 15 s while out.
    var internetTask: Task<Void, Never>?
    private var preferencesCancellable: AnyCancellable?
    private var notificationsCancellable: AnyCancellable?
    private var visibleViews = 0
    /// The live activity's state, for `liveActivityState`.
    let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    /// The lock screen row, for `lockScreenStatus`.
    let lockScreenSubject = CurrentValueSubject<LockScreenStatusEntry?, Never>(nil)
    /// What Droppy last said about the live activity: "compact",
    /// "secondary", or the reason it isn't showing. For Settings.
    @Published var activitySeat: String?

    @Published private(set) var result: LiteMe?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var lastError: LiteError?
    @Published private(set) var isLoading = false
    /// This Mac's side of the network. Read locally, so it needs no consent.
    @Published private(set) var localNetwork: LocalNetwork?
    /// The last local network that had an address and wasn't a VPN's
    /// tunnel, for the local alert.
    private var lastLocalWithAddress: LocalNetwork?
    /// The last network the Mac was online with, for the tunnel alert.
    private var lastOnline: LocalNetwork?
    /// When the Mac's tunnel last said the VPN changed, so dotquad.app's
    /// answer a moment later doesn't say it again.
    private var tunnelAlertAt: Date?
    /// What happened to the last alert, for the test button in Settings.
    @Published private(set) var lastAlertOutcome: AlertOutcome?
    /// Why the last notification didn't show, when one was tried and didn't.
    @Published private(set) var lastNotificationIssue: NotificationIssue?
    /// Why the last HUD didn't show, when one was tried and didn't.
    @Published private(set) var lastHUDIssue: HUDIssue?

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host
        preferencesCancellable = host.preferences.didChange.sink { [weak self] key in
            Task { @MainActor [weak self] in
                guard let self, key.hasSuffix(Self.lookupsOnKey) || key == Self.lookupsOnKey else { return }
                self.lookupsDidChange()
            }
        }
        notificationsCancellable = host.notifications.events.sink { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        startPathMonitor()
        startInternetWatch()
        refreshLocalNetwork()
        // With public alerts on, a first answer to compare the next one with.
        if watchesPublic { refreshIfAllowed() }
        updateActivity()
    }

    public func deactivate() {
        activitySubject.send(nil)
        lockScreenSubject.send(nil)
        inFlight?.cancel()
        inFlight = nil
        networkTask?.cancel()
        networkTask = nil
        moveTask?.cancel()
        moveTask = nil
        internetTask?.cancel()
        internetTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        preferencesCancellable?.cancel()
        preferencesCancellable = nil
        notificationsCancellable?.cancel()
        notificationsCancellable = nil
        visibleViews = 0
        isLoading = false
        host = nil
    }

    // MARK: Consent

    /// The opt-in. Off until the user turns it on; nothing is sent before.
    var lookupsOn: Bool {
        host?.preferences.value(forKey: Self.lookupsOnKey, default: false) ?? false
    }

    var lookupsOnBinding: Binding<Bool> {
        Binding(
            get: { self.lookupsOn },
            set: { self.setLookupsOn($0) }
        )
    }

    func setLookupsOn(_ on: Bool) {
        host?.preferences.setValue(on, forKey: Self.lookupsOnKey)
        objectWillChange.send()
        lookupsDidChange()
    }

    // MARK: Alerts

    /// Banner when the public IP changes. Off until the user turns it on,
    /// and only with lookups on.
    var alertsPublic: Bool {
        host?.preferences.value(forKey: Self.alertPublicKey, default: false) ?? false
    }

    /// Alert when the VPN turns off or on: the Mac starting or stopping
    /// sending everything through a tunnel, and, with lookups on, dotquad.app's
    /// VPN flag for the public IP. Off until the user turns it on.
    var alertsVPN: Bool {
        host?.preferences.value(forKey: Self.alertVPNKey, default: false) ?? false
    }

    /// Either public alert: both need an answer after each network change.
    var watchesPublic: Bool { lookupsOn && (alertsPublic || alertsVPN) }

    /// Banner when the local IP changes. Read from the Mac; sends nothing.
    var alertsLocal: Bool {
        host?.preferences.value(forKey: Self.alertLocalKey, default: false) ?? false
    }

    var alertsPublicBinding: Binding<Bool> {
        Binding(get: { self.alertsPublic }, set: { self.setPreference($0, Self.alertPublicKey) })
    }

    var alertsVPNBinding: Binding<Bool> {
        Binding(get: { self.alertsVPN }, set: { self.setPreference($0, Self.alertVPNKey) })
    }

    var alertsLocalBinding: Binding<Bool> {
        Binding(get: { self.alertsLocal }, set: { self.setPreference($0, Self.alertLocalKey) })
    }

    /// How alerts show: as a HUD in the island (the default) or as a
    /// notification in Droppy's banners.
    var alertStyle: AlertStyle {
        AlertStyle(rawValue: host?.preferences.value(forKey: Self.alertStyleKey, default: AlertStyle.hud.rawValue) ?? "") ?? .hud
    }

    var alertStyleBinding: Binding<AlertStyle> {
        Binding(
            get: { self.alertStyle },
            set: {
                self.host?.preferences.setValue($0.rawValue, forKey: Self.alertStyleKey)
                self.objectWillChange.send()
            }
        )
    }

    /// The VPN live activity. Off until the user turns it on.
    var activityOn: Bool {
        host?.preferences.value(forKey: Self.activityKey, default: false) ?? false
    }

    var activityOnBinding: Binding<Bool> {
        Binding(get: { self.activityOn }, set: { self.setPreference($0, Self.activityKey) })
    }

    var bannersGranted: Bool { host?.isGranted(.notchBanner) ?? false }
    var hudGranted: Bool { host?.isGranted(.hud) ?? false }

    private func setPreference(_ on: Bool, _ key: String) {
        host?.preferences.setValue(on, forKey: key)
        objectWillChange.send()
        // Turned on with nothing to compare yet: get a first answer now, so
        // the next change has something to be compared with.
        if key == Self.alertInternetKey || key == Self.internetActivityKey {
            startInternetWatch()
        } else if on, key != Self.alertLocalKey, key != Self.activityKey, result == nil {
            refreshIfAllowed()
        }
        updateActivity()
    }

    /// Shows an alert the way the user chose: as a HUD in the island, the way
    /// Droppy shows Caps Lock and battery, or as a notification in Droppy's
    /// banners. When Droppy refuses that one (the shelf is open, Focus, a
    /// switched-off permission), it tries the other.
    @discardableResult
    func show(_ alert: IPAlert) -> AlertOutcome {
        guard let host else { return record(.refused, alert) }
        let tint = alert.isWarning ? LiteColor.flag : LiteColor.signal
        let kind = alert.kind
        let card = DropletHUDCard(
            title: alert.title,
            message: alert.body,
            systemImage: alert.symbol,
            tint: tint,
            actions: kind == .internet ? [] : [
                DropletHUDAction(id: "copy", title: "Copy") { [weak self] in self?.perform("copy", for: kind) },
                DropletHUDAction(id: "open", title: kind == .localIP ? "Look Up" : "Open", isPrimary: true) { [weak self] in
                    self?.perform("open", for: kind)
                },
            ]
        )
        let request = DropletHUDRequest(
            id: "alert-\(kind.rawValue)",
            duration: 6,
            priority: .normal,
            accessibilityLabel: "\(alert.title). \(alert.body)",
            card: card,
            isExpanded: false
        ) {
            Image(systemName: alert.symbol)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            Text(verbatim: alert.short)
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
        }
        let notification = DropletNotification(
            id: kind.rawValue,
            title: alert.title,
            body: alert.body,
            systemImage: alert.symbol,
            actions: kind == .internet ? [] : [
                DropletNotificationAction(id: "copy", title: "Copy"),
                DropletNotificationAction(id: "open", title: kind == .localIP ? "Look Up" : "Open"),
            ]
        )
        lastNotificationIssue = nil
        lastHUDIssue = nil
        let asHUD = {
            guard self.hudGranted else { self.lastHUDIssue = .notGranted; return false }
            guard host.hud.present(request) else { self.lastHUDIssue = .refused; return false }
            return true
        }
        let asNotification = {
            guard self.bannersGranted else { self.lastNotificationIssue = .notGranted; return false }
            guard host.notifications.post(notification) else { self.lastNotificationIssue = .refused; return false }
            return true
        }
        switch alertStyle {
        case .hud:
            if asHUD() { return record(.hud, alert) }
            if asNotification() { return record(.notification, alert) }
        case .notification:
            if asNotification() { return record(.notification, alert) }
            if asHUD() { return record(.hud, alert) }
        }
        return record(.refused, alert)
    }

    private func record(_ outcome: AlertOutcome, _ alert: IPAlert) -> AlertOutcome {
        host?.log.notice("alert \(alert.kind.rawValue): \(outcome.rawValue), notification \(lastNotificationIssue?.rawValue ?? "-"), hud \(lastHUDIssue?.rawValue ?? "-")")
        lastAlertOutcome = outcome
        return outcome
    }

    /// The test button in Settings.
    func showTestAlert() {
        show(IPChange.test)
    }

    private func perform(_ action: String, for kind: IPAlert.Kind) {
        switch (action, kind) {
        case (_, .internet): break
        case ("copy", .localIP): copyLocalIP()
        case ("copy", _): copyIP()
        case ("open", .localIP): openLookUp()
        case ("open", _): openOnWebsite()
        default: break
        }
    }

    private func handle(_ event: DropletNotificationEvent) {
        switch event {
        case .action(let id, let action):
            if let kind = IPAlert.Kind(rawValue: id) { perform(action, for: kind) }
        case .opened(let id):
            if let kind = IPAlert.Kind(rawValue: id), kind == .publicIP || kind == .vpn { openOnWebsite() }
        default:
            break
        }
    }

    private func lookupsDidChange() {
        if lookupsOn {
            if visibleViews > 0 { refreshIfAllowed() }
        } else {
            // Off means forgotten: drop the answer and any request in flight.
            inFlight?.cancel()
            inFlight = nil
            networkTask?.cancel()
            networkTask = nil
            moveTask?.cancel()
            moveTask = nil
            policy.reset()
            result = nil
            updatedAt = nil
            lastError = nil
            isLoading = false
        }
        updateActivity()
    }

    var networkGranted: Bool { host?.isGranted(.networkClient) ?? false }
    var copyGranted: Bool { host?.isGranted(.clipboardWrite) ?? false }

    // MARK: Visibility

    /// Called by the widget and the tile's content as they appear and go.
    /// Requests follow what's on screen.
    func viewDidAppear() {
        visibleViews += 1
        refreshLocalNetwork()
        refreshIfAllowed()
    }

    func viewDidDisappear() {
        visibleViews = max(0, visibleViews - 1)
    }

    // MARK: Fetching

    /// A request, if the policy allows one now. For the views.
    func refreshIfAllowed() {
        guard lookupsOn, networkGranted, policy.mayFetch(now: Date()) else { return }
        Task { @MainActor [weak self] in
            _ = try? await self?.fetch()
        }
    }

    /// The current answer, from memory when it's under 5 minutes old and the
    /// network hasn't changed, otherwise from dotquad.app. For the MCP tools.
    func currentAnswer() async throws -> LiteMe {
        guard lookupsOn else { throw DotquadLiteToolError.lookupsOff }
        guard networkGranted else { throw DotquadLiteToolError.networkRefused }
        let now = Date()
        if let result, policy.isFresh(updatedAt, now: now) { return result }
        if let wait = policy.blockedFor(now: now) {
            if let result { return result }
            throw LiteError.rateLimited(retryAfter: wait)
        }
        return try await fetch()
    }

    /// One request at a time: a second caller waits for the first.
    @discardableResult
    private func fetch(alerting: Bool = true) async throws -> LiteMe {
        if let inFlight { return try await inFlight.value }
        policy.didAttempt(at: Date())
        isLoading = true
        let client = self.client
        let task = Task.detached(priority: .utility) { try await client.fetch() }
        inFlight = task
        defer {
            inFlight = nil
            isLoading = false
        }
        do {
            let me = try await task.value
            // Switched off while the request ran: keep nothing.
            guard lookupsOn else { throw CancellationError() }
            let announced = tunnelAlertAt.map { Date().timeIntervalSince($0) < 120 } ?? false
            if alerting, watchesPublic,
               let alert = IPChange.publicAlert(
                   old: result, new: me, ipChanges: alertsPublic, vpnChanges: alertsVPN, vpnAnnounced: announced
               ) {
                show(alert)
            }
            result = me
            updatedAt = Date()
            updateActivity()
            lastError = nil
            return me
        } catch let error as LiteError {
            if case .rateLimited(let wait) = error {
                policy.didRateLimit(retryAfter: wait, now: Date())
            }
            lastError = error
            if case .rateLimited = error {} else { checkInternetSoon() }
            host?.log.notice("lookup failed: \(error)")
            throw error
        }
    }

    // MARK: Network changes

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        hasSeenPath = false
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.pathDidUpdate(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "app.dotquad.lite.path", qos: .utility))
        pathMonitor = monitor
    }

    /// The first callback is the current path, not a change.
    private func pathDidUpdate(satisfied: Bool) {
        pathSatisfied = satisfied
        internetPathChanged()
        refreshLocalNetwork()
        // DHCP and the router can land a moment after the path changes.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.refreshLocalNetwork()
        }
        guard hasSeenPath else { hasSeenPath = true; return }
        networkDidChange()
    }

    /// Re-reads the interface, addresses, router and DNS. Local and cheap.
    func refreshLocalNetwork() {
        let now = LocalNetwork.read()
        guard now != localNetwork else { return }
        if let now {
            // Compare with the last network the Mac was online with, so a
            // moment offline while the VPN connects still counts.
            let vpnAlert = alertsVPN ? IPChange.tunnelAlert(old: lastOnline, new: now) : nil
            if let last = lastOnline, IPChange.moved(from: last, to: now) {
                networkMoved(vpnAlert: vpnAlert)
            }
            lastOnline = now
        }
        // Compare with the last address seen, so offline and back on the
        // same address says nothing.
        if alertsLocal, let alert = IPChange.localAlert(old: lastLocalWithAddress, new: now) { show(alert) }
        if let now, now.address != nil, !now.isTunnel { lastLocalWithAddress = now }
        localNetwork = now
        updateActivity()
    }

    /// The Mac moved: a VPN connected, dropped or switched servers, or it
    /// joined another network. Ask for the new public IP straight away, and
    /// once more if the answer is still the old one, since the VPN's route
    /// can take a few seconds to carry traffic. The VPN alert waits for the
    /// answer, so it can say the new IP.
    private func networkMoved(vpnAlert: IPAlert?) {
        // The VPN alert goes up at once; the new IP joins it when it arrives.
        if let vpnAlert {
            tunnelAlertAt = Date()
            show(vpnAlert)
        }
        guard lookupsOn, networkGranted else { return }
        // This check replaces the path monitor's slower one.
        networkTask?.cancel()
        networkTask = nil
        moveTask?.cancel()
        let before = result
        // The VPN alert says the IP change itself; without one, the public
        // IP alert does.
        let alerting = vpnAlert == nil
        moveTask = Task { @MainActor [weak self] in
            // A moment for the route to settle, and a little spread so Macs
            // on one VPN server don't all ask in the same second.
            try? await Task.sleep(for: .seconds(1 + Double.random(in: 0...2)))
            guard let self, !Task.isCancelled else { return }
            var after = await self.checkAfterMove(alerting: alerting)
            if before != nil, after == nil || after?.ip == before?.ip {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                after = await self.checkAfterMove(alerting: alerting) ?? after
            }
            self.moveTask = nil
            // Still on screen: the same id updates it in place with the IP.
            // Gone already: the widget, the tile and the activity show it,
            // so don't pop up a second time.
            if let vpnAlert, let shownAt = self.tunnelAlertAt, Date().timeIntervalSince(shownAt) < 5.5, after != nil {
                self.show(IPChange.withPublic(vpnAlert, before: before, after: after))
            }
        }
    }

    /// One request after a move, unless a 429 still says wait.
    private func checkAfterMove(alerting: Bool) async -> LiteMe? {
        guard lookupsOn, networkGranted, policy.blockedFor(now: Date()) == nil else { return nil }
        policy.networkDidChange()
        return try? await fetch(alerting: alerting)
    }

    private func networkDidChange() {
        guard lookupsOn else { return }
        // The Mac's own move check is already asking.
        guard moveTask == nil else { return }
        policy.networkDidChange()
        // Nobody looking and no alert to give: the next look fetches, since
        // the answer is now stale. With public alerts on, ask anyway: that's
        // what the user turned them on for.
        guard visibleViews > 0 || watchesPublic else { return }
        networkTask?.cancel()
        let wait = RefreshPolicy.jitter()
        networkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.visibleViews > 0 || self.watchesPublic else { return }
            // Right after a VPN connects the request can fail or still leave
            // by the old route. Ask once more a little later if it failed.
            guard self.lookupsOn, self.networkGranted, self.policy.mayFetch(now: Date()) else { return }
            if (try? await self.fetch()) == nil {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self.policy.networkDidChange()
                self.refreshIfAllowed()
            }
        }
    }

    // MARK: Actions

    /// Copies the IP. Returns false when Droppy refused (clipboard access off).
    @discardableResult
    func copyIP() -> Bool {
        copy(result?.ip)
    }

    /// Copies the local address. Returns false when there's none or Droppy refused.
    @discardableResult
    func copyLocalIP() -> Bool {
        copy(localNetwork?.address)
    }

    private func copy(_ text: String?) -> Bool {
        guard let text, let host, copyGranted else { return false }
        let copied = host.workspace.copyToPasteboard(text)
        host.feedback.play(copied ? .success : .failure)
        return copied
    }

    func openOnWebsite() {
        let url = result.flatMap { HandOff.ipLookup($0.ip) } ?? HandOff.home
        host?.workspace.open(url)
    }

    func openWebsite() {
        open(HandOff.home)
    }

    /// Opens a dotquad.app link in the browser. Only https://dotquad.app.
    func open(_ url: URL) {
        guard url.scheme == "https", url.host == HandOff.site.host else { return }
        host?.workspace.open(url)
    }

    /// The website tools, from the Command Center tile.
    func openLookUp() {
        host?.workspace.openSettings()
    }

    /// What the widget and tile show under the answer when the last request failed.
    var staleNote: String? {
        guard let updatedAt else { return nil }
        guard lastError != nil else { return nil }
        return LiteText.updated(since: updatedAt)
    }
}

/// How alerts show, in Droppy's own words.
enum AlertStyle: String, CaseIterable {
    /// In the island for a few seconds, like Caps Lock.
    case hud
    /// In Droppy's banners, until the user sees it.
    case notification

    var title: String {
        switch self {
        case .hud: return "HUD"
        case .notification: return "Notification"
        }
    }
}

/// Why Droppy didn't show a notification or a HUD.
enum NotificationIssue: String {
    /// Droppy hasn't granted the capability.
    case notGranted = "not-granted"
    /// Droppy was asked and said no.
    case refused
}

typealias HUDIssue = NotificationIssue

/// Where the last alert went, for Settings.
enum AlertOutcome: String {
    case hud
    case notification
    /// Droppy took neither.
    case refused
}

enum DotquadLiteToolError: Error, CustomStringConvertible {
    case lookupsOff
    case networkRefused
    case unknownTool(String)
    case unexpectedArguments

    var description: String {
        switch self {
        case .lookupsOff:
            return "Dotquad Lite's lookups are off. Turn on \"Look up my public IP\" in Droppy Settings, Dotquad Lite."
        case .networkRefused:
            return "Droppy has network access switched off for Dotquad Lite."
        case .unknownTool(let name):
            return "Dotquad Lite has no tool named \(name)."
        case .unexpectedArguments:
            return "This tool takes no arguments. Call it with an empty object."
        }
    }
}
