//
//  CommandCenterTile.swift
//  DotquadLite
//
//  The Command Center tile: the IP as its title and a shield when it's a VPN.
//  Pressing it opens the public IP with its status, then the local network:
//  the interface and local IP, the router and the DNS servers.
//

import SwiftUI
import DroppyKit

extension DotquadLiteDroplet: MenuBarExtraProviding {
    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        let me = lookupsOn ? result : nil
        let symbol = me?.vpn == true ? "lock.shield" : "network"
        return MenuBarExtraDescriptor(title: me?.ip ?? "My IP", systemImage: symbol) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(MyIPTileContent(droplet: self))
        }
    }
}

private struct MyIPTileContent: View {
    @ObservedObject var droplet: DotquadLiteDroplet

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            publicSection
            Divider().opacity(0.5)
            localSection
            HStack(spacing: DroppySpacing.sm) {
                Button("Open on dotquad.app") { droplet.openOnWebsite() }
                Button("Look Up…") { droplet.openLookUp() }
                    .help("Look up an IP, domain or link on dotquad.app")
            }
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
        }
        .foregroundStyle(AdaptiveColors.primaryTextAuto)
        .padding(.vertical, DroppySpacing.xs)
        .frame(minWidth: 240, alignment: .leading)
        .onAppear { droplet.viewDidAppear() }
        .onDisappear { droplet.viewDidDisappear() }
    }

    @ViewBuilder
    private var publicSection: some View {
        if !droplet.lookupsOn {
            Text(LiteText.consentNotice)
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Turn On") { droplet.setLookupsOn(true) }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
        } else if let me = droplet.result {
            DotMap(me: me, ink: AdaptiveColors.primaryTextAuto, inkOpacity: 0.25)
                .frame(maxWidth: .infinity)
            HStack(alignment: .center, spacing: DroppySpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: me.ip)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                    HStack(spacing: DroppySpacing.xsm) {
                        if let place = LiteText.place(me) {
                            Text([LiteText.flag(me.country), place].compactMap { $0 }.joined(separator: " "))
                                .font(.system(size: 11))
                                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                                .lineLimit(1)
                        }
                        StatusChip(me: me, size: 10)
                    }
                }
                Spacer(minLength: DroppySpacing.md)
                CopyButton(droplet: droplet, target: .publicIP, diameter: 28)
            }
            if let note = droplet.staleNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.secondaryTextAuto)
            }
        } else {
            Text(droplet.lastError?.message ?? "Looking up your IP…")
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var localSection: some View {
        if let local = droplet.localNetwork {
            HStack(spacing: DroppySpacing.sm) {
                row(local.interfaceLabel, local.address ?? "No address", symbol: local.symbol)
                CopyButton(droplet: droplet, target: .localIP, diameter: 28)
            }
            if let router = local.router {
                row("Router", router, symbol: "wifi.router")
            }
            if let dns = LiteText.dnsSummary(local.dns) {
                row("DNS", dns, symbol: "point.3.connected.trianglepath.dotted")
            }
        } else {
            row("Local network", "Offline", symbol: "wifi.slash")
        }
    }

    private func row(_ label: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                .lineLimit(1)
            Spacer(minLength: DroppySpacing.sm)
            Text(verbatim: value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}
