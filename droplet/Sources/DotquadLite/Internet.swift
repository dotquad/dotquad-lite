//
//  Internet.swift
//  DotquadLite
//
//  No internet: an alert when the Mac is connected but nothing loads (or a
//  network wants a sign-in), "Back online" when it works again, and a live
//  activity while it's out. Plain offline is Droppy's own No internet HUD;
//  the activity covers it too, since that HUD only pops up once.
//
//  Checks run only while one of the two switches is on: after each network
//  change, after a failed lookup, every 2 minutes while online and every 15
//  seconds while out. See InternetCheck for what a check sends.
//

import Foundation
import SwiftUI

extension DotquadLiteDroplet {
    /// Alert when connected but there's no internet, and when it's back.
    var alertsInternet: Bool {
        host?.preferences.value(forKey: Self.alertInternetKey, default: false) ?? false
    }

    /// The No internet live activity.
    var internetActivityOn: Bool {
        host?.preferences.value(forKey: Self.internetActivityKey, default: false) ?? false
    }

    var alertsInternetBinding: Binding<Bool> {
        Binding(get: { self.alertsInternet }, set: { self.setInternetPreference($0, Self.alertInternetKey) })
    }

    var internetActivityBinding: Binding<Bool> {
        Binding(get: { self.internetActivityOn }, set: { self.setInternetPreference($0, Self.internetActivityKey) })
    }

    var watchesInternet: Bool { alertsInternet || internetActivityOn }

    private func setInternetPreference(_ on: Bool, _ key: String) {
        host?.preferences.setValue(on, forKey: key)
        objectWillChange.send()
        startInternetWatch()
    }

    /// Starts the check loop, or stops it and forgets the state when both
    /// switches are off. `delay` waits before the first check.
    func startInternetWatch(after delay: TimeInterval = 0) {
        internetTask?.cancel()
        guard watchesInternet, networkGranted else {
            internetTask = nil
            connectivity = nil
            outSince = nil
            updateActivity()
            return
        }
        internetTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkInternet()
                let wait: TimeInterval = self.connectivity?.isOut == true ? 15 : 120
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// The network changed. Offline is known at once; otherwise check
    /// after a moment, once addresses and routes have settled.
    func internetPathChanged() {
        guard watchesInternet else { return }
        if !pathSatisfied { setConnectivity(.offline) }
        startInternetWatch(after: 2)
    }

    /// A lookup failed: maybe the internet is out. Check now rather than
    /// waiting up to 2 minutes.
    func checkInternetSoon() {
        guard watchesInternet, connectivity?.isOut != true else { return }
        startInternetWatch()
    }

    private func checkInternet() async {
        guard pathSatisfied else { setConnectivity(.offline); return }
        let answer = await InternetCheck.run()
        guard !Task.isCancelled, watchesInternet else { return }
        setConnectivity(pathSatisfied ? answer : .offline)
    }

    private func setConnectivity(_ new: Connectivity) {
        let old = connectivity
        guard old != new else { return }
        if new.isOut, old?.isOut != true { outSince = Date() }
        let outFor = outSince.map { Date().timeIntervalSince($0) }
        if alertsInternet,
           let alert = IPChange.internetAlert(old: old, new: new, network: localNetwork, outFor: outFor) {
            show(alert)
        }
        if !new.isOut { outSince = nil }
        connectivity = new
        host?.log.notice("internet: \(new.rawValue)")
        updateActivity()
    }
}
