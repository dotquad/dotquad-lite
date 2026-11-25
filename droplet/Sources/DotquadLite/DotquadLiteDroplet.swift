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
public final class DotquadLiteDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "dotquad-lite"
    /// Sent as `User-Agent: DotquadLite/<version>`. Keep it equal to droplet.json.
    public nonisolated static let version = "1.0.0"

    static let lookupsOnKey = "lookupsOn"
    static let alertPublicKey = "alertPublicIPChange"
    static let alertLocalKey = "alertLocalIPChange"
    static let alertVPNKey = "alertVPNChange"

    private(set) var host: DropletHost?
    private let client = LiteClient(version: DotquadLiteDroplet.version)
    private var policy = RefreshPolicy()
    private var inFlight: Task<LiteMe, Error>?
    private var networkTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var hasSeenPath = false
    private var preferencesCancellable: AnyCancellable?
    private var notificationsCancellable: AnyCancellable?
    private var visibleViews = 0

    @Published private(set) var result: LiteMe?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var lastError: LiteError?
    @Published private(set) var isLoading = false
    /// This Mac's side of the network. Read locally, so it needs no consent.
    @Published private(set) var localNetwork: LocalNetwork?
    /// The last local network that had an address, for the local alert.
    private var lastLocalWithAddress: LocalNetwork?

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
        refreshLocalNetwork()
        // With public alerts on, a first answer to compare the next one with.
        if watchesPublic { refreshIfAllowed() }
    }

    public func deactivate() {
        inFlight?.cancel()
        inFlight = nil
        networkTask?.cancel()
        networkTask = nil
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

    /// Banner when the VPN turns off or on, as dotquad.app sees the public
    /// IP. Off until the user turns it on, and only with lookups on.
    var alertsVPN: Bool {
        host?.preferences.value(forKey: Self.alertVPNKey, default: false) ?? false
    }

    /// Either public alert: both need an answer after each network change.
    var watchesPublic: Bool { alertsPublic || alertsVPN }

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

    var bannersGranted: Bool { host?.isGranted(.notchBanner) ?? false }

    private func setPreference(_ on: Bool, _ key: String) {
        host?.preferences.setValue(on, forKey: key)
        objectWillChange.send()
        // Turned on with nothing to compare yet: get a first answer now, so
        // the next change has something to be compared with.
        if on, key != Self.alertLocalKey, result == nil { refreshIfAllowed() }
    }

    private func post(_ alert: IPAlert) {
        guard let host, bannersGranted else { return }
        host.notifications.post(DropletNotification(
            id: alert.kind.rawValue,
            title: alert.title,
            body: alert.body,
            systemImage: alert.symbol,
            actions: [
                DropletNotificationAction(id: "copy", title: "Copy"),
                DropletNotificationAction(id: "open", title: alert.kind == .publicIP ? "Open" : "Look Up"),
            ]
        ))
    }

    private func handle(_ event: DropletNotificationEvent) {
        switch event {
        case .action(let id, let action):
            let isPublic = id == IPAlert.Kind.publicIP.rawValue
            if action == "copy" {
                if isPublic { copyIP() } else { copyLocalIP() }
            } else if action == "open" {
                if isPublic { openOnWebsite() } else { openLookUp() }
            }
        case .opened(let id):
            if id == IPAlert.Kind.publicIP.rawValue { openOnWebsite() }
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
            policy.reset()
            result = nil
            updatedAt = nil
            lastError = nil
            isLoading = false
        }
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
    private func fetch() async throws -> LiteMe {
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
            if watchesPublic,
               let alert = IPChange.publicAlert(old: result, new: me, ipChanges: alertsPublic, vpnChanges: alertsVPN) {
                post(alert)
            }
            result = me
            updatedAt = Date()
            lastError = nil
            return me
        } catch let error as LiteError {
            if case .rateLimited(let wait) = error {
                policy.didRateLimit(retryAfter: wait, now: Date())
            }
            lastError = error
            host?.log.notice("lookup failed: \(error)")
            throw error
        }
    }

    // MARK: Network changes

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        hasSeenPath = false
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.pathDidUpdate() }
        }
        monitor.start(queue: DispatchQueue(label: "app.dotquad.lite.path", qos: .utility))
        pathMonitor = monitor
    }

    /// The first callback is the current path, not a change.
    private func pathDidUpdate() {
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
        // Compare with the last address seen, so offline and back on the
        // same address says nothing.
        if alertsLocal, let alert = IPChange.localAlert(old: lastLocalWithAddress, new: now) { post(alert) }
        if now?.address != nil { lastLocalWithAddress = now }
        localNetwork = now
    }

    private func networkDidChange() {
        guard lookupsOn else { return }
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
            self.refreshIfAllowed()
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
