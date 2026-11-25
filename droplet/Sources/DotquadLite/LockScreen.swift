//
//  LockScreen.swift
//  DotquadLite
//
//  A row on Droppy's lock screen: VPN on or off and the country your IP
//  appears in, or that the internet is out. Off until the user turns it on.
//  The IP itself shows only with a second switch, also off: anyone walking
//  past can read a lock screen.
//
//  It sends nothing and runs no timer of its own: it republishes when what
//  it says changes, from the same places the live activity does.
//

import Combine
import DroppyKit
import SwiftUI

extension DotquadLiteDroplet: LockScreenStatusProviding {
    public var lockScreenStatus: AnyPublisher<LockScreenStatusEntry?, Never> {
        lockScreenSubject.eraseToAnyPublisher()
    }

    var lockScreenOn: Bool {
        host?.preferences.value(forKey: Self.lockScreenKey, default: false) ?? false
    }

    var lockScreenIPOn: Bool {
        host?.preferences.value(forKey: Self.lockScreenIPKey, default: false) ?? false
    }

    var lockScreenOnBinding: Binding<Bool> {
        Binding(get: { self.lockScreenOn }, set: { self.setLockScreenPreference($0, Self.lockScreenKey) })
    }

    var lockScreenIPBinding: Binding<Bool> {
        Binding(get: { self.lockScreenIPOn }, set: { self.setLockScreenPreference($0, Self.lockScreenIPKey) })
    }

    private func setLockScreenPreference(_ on: Bool, _ key: String) {
        host?.preferences.setValue(on, forKey: key)
        objectWillChange.send()
        updateLockScreen()
    }

    /// Publishes the row, or nil when the switch is off. Only when it changes.
    func updateLockScreen() {
        let entry: LockScreenStatusEntry?
        if lockScreenOn {
            let line = LockScreenText.line(
                vpnOn: vpnIsOn,
                connectivity: connectivity,
                country: lookupsOn ? result?.country : nil,
                ip: lookupsOn ? result?.ip : nil,
                showIP: lockScreenIPOn
            )
            entry = LockScreenStatusEntry(
                id: "status",
                systemImage: line.symbol,
                text: line.text,
                detail: line.detail,
                roundedCenterText: line.center,
                roundedBottomText: line.bottom,
                progress: nil,
                ticksEverySecond: false
            )
        } else {
            entry = nil
        }
        guard lockScreenSubject.value != entry else { return }
        lockScreenSubject.send(entry)
    }
}
