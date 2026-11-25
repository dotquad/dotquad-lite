//
//  ShelfWidget.swift
//  DotquadLite
//
//  The My IP widget, on Droppy's own widget layout (the one Pomodoro and
//  System Stats use), so its spacing, type and controls match theirs.
//
//  Alone on the shelf, public on the left and this Mac's side on the right:
//
//      My IP                                       ⎘  ⌕  ↗
//      203.0.113.7            ·:·::●:·  │ Wi-Fi    192.168.1.23 ⎘
//      🇳🇱 Amsterdam  [VPN]    ·::·:·:·  │ Router    192.168.1.1
//      M247 Europe · AS9009    ·:  ·:    │ DNS         1.1.1.1 +1
//
//  The map is the world in dots with a pin where the IP appears, in the
//  status color.
//
//  Beside another widget: the IP, the VPN dot and the local IP.
//
//  The local half is read from the Mac and sends nothing, so it shows
//  before the user turns lookups on.
//

import SwiftUI
import DroppyKit

/// The widget's content heights: Droppy adds its own insets.
private enum MyIPSize {
    static let singleWidth: CGFloat = 560
    static let singleHeight: CGFloat = 112
    static let splitWidth: CGFloat = 210
    static let splitHeight: CGFloat = 76
}

extension DotquadLiteDroplet: ShelfWidgetCompositionProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: "my-ip",
                title: "My IP",
                systemImage: "network",
                layoutTraits: ShelfWidgetLayoutTraits(
                    single: ShelfWidgetModeSize(width: MyIPSize.singleWidth, contentHeight: MyIPSize.singleHeight),
                    split: ShelfWidgetModeSize(width: MyIPSize.splitWidth, contentHeight: MyIPSize.splitHeight),
                    header: .standard
                ),
                searchKeywords: ["ip", "public ip", "local ip", "router", "dns", "vpn", "location", "network", "asn", "dotquad"]
            ),
            lookUpDescriptor,
        ]
    }

    public func makeWidgetContent(_ id: ShelfWidgetID, layout: ShelfWidgetLayout) -> AnyView {
        if id == Self.lookUpWidgetID { return AnyView(LookUpWidget(droplet: self)) }
        return AnyView(MyIPWidget(droplet: self, isPreview: layout.isPreview))
    }
}

private struct MyIPWidget: View {
    @ObservedObject var droplet: DotquadLiteDroplet
    let isPreview: Bool
    @Environment(\.dropletWidgetLayout) private var layout
    @State private var isCountedVisible = false

    private var metrics: DroppyWidgetMetrics { layout?.metrics ?? .single }
    private var isSplit: Bool { layout?.isSplit ?? false }
    /// The map's height: a little over half the content, so it sits between
    /// the header and the card's bottom with room to breathe.
    private var mapHeight: CGFloat { (layout?.contentSize.height ?? MyIPSize.singleHeight) * 0.56 }

    var body: some View {
        ShelfWidgetScaffold("My IP", systemImage: "network") {
            if isSplit {
                CopyButton(droplet: droplet, target: shownResult == nil ? .localIP : .publicIP)
            } else {
                CopyButton(droplet: droplet, target: .publicIP)
                Button {
                    droplet.openLookUp()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Look up an IP, domain or link on dotquad.app")
                .accessibilityLabel("Look Up")
                Button {
                    droplet.openOnWebsite()
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .help("Open on dotquad.app")
                .accessibilityLabel("Open on dotquad.app")
            }
        } content: {
            DropletWidgetComposition {
                single
            } split: {
                split
            }
        }
        .onAppear { syncVisibility(true) }
        .onDisappear { syncVisibility(false) }
    }

    /// Previews never fetch: only a widget someone is looking at does.
    private func syncVisibility(_ mounted: Bool) {
        let active = mounted && !isPreview
        guard active != isCountedVisible else { return }
        isCountedVisible = active
        if active { droplet.viewDidAppear() } else { droplet.viewDidDisappear() }
    }

    /// The answer, when lookups are on and there is one.
    private var shownResult: LiteMe? {
        droplet.lookupsOn ? droplet.result : nil
    }

    // MARK: Alone

    private var single: some View {
        HStack(alignment: .center, spacing: DroppySpacing.md) {
            publicColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            DotMap(
                me: shownResult,
                ink: layout?.foreground ?? AdaptiveColors.notchSurfacePrimaryText,
                inkOpacity: shownResult == nil ? 0.14 : 0.26
            )
            .frame(width: mapHeight * CGFloat(WorldDots.columns) / CGFloat(WorldDots.rows.count), height: mapHeight)
            Rectangle()
                .fill(AdaptiveColors.notchSurfaceTertiaryText.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 4)
            localColumn
                .frame(width: (layout?.contentSize.width ?? MyIPSize.singleWidth) * 0.36)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var publicColumn: some View {
        if !droplet.lookupsOn {
            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                Text(LiteText.consentNotice)
                    .droppyWidgetText(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On") { droplet.setLookupsOn(true) }
                    .buttonStyle(DroppyWashButtonStyle(tone: .accent(LiteColor.signal)))
            }
        } else {
            publicText
        }
    }

    @ViewBuilder
    private var publicText: some View {
        if !droplet.networkGranted {
            caption("Droppy has network access switched off for Dotquad Lite.")
        } else if let me = droplet.result {
            VStack(alignment: .leading, spacing: 3) {
                IPFigure(text: me.ip, size: metrics.figureTextSize)
                HStack(spacing: DroppySpacing.xsm) {
                    if let place = LiteText.place(me) {
                        let flag = LiteText.flag(me.country)
                        ViewThatFits(in: .horizontal) {
                            placeText([flag, place])
                            placeText([flag, LiteText.shortPlace(me)])
                        }
                        .help("\(place). \(LiteText.locationTooltip)")
                    }
                    StatusChip(me: me, size: metrics.captionTextSize)
                }
                if let line = droplet.staleNote ?? LiteText.network(me) {
                    Text(line)
                        .droppyWidgetText(.caption)
                        .lineLimit(1)
                        .help(droplet.lastError?.message ?? "")
                }
            }
        } else if let error = droplet.lastError {
            caption(error.message)
        } else {
            caption("Looking up your IP…")
        }
    }

    private func placeText(_ parts: [String?]) -> some View {
        Text(parts.compactMap { $0 }.joined(separator: " "))
            .droppyWidgetText(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .droppyWidgetText(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var localColumn: some View {
        if let local = droplet.localNetwork {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                HStack(spacing: DroppySpacing.xsm) {
                    ShelfWidgetValueRow(local.kind ?? local.interface, value: local.address ?? "No address", systemImage: local.symbol)
                        .help(local.interfaceLabel)
                    CopyButton(droplet: droplet, target: .localIP, diameter: 18)
                }
                ShelfWidgetValueRow("Router", value: local.router ?? "None", systemImage: "wifi.router")
                ShelfWidgetValueRow("DNS", value: LiteText.dnsSummary(local.dns) ?? "None", systemImage: "point.3.connected.trianglepath.dotted")
                    .help(local.dns.joined(separator: ", "))
            }
        } else {
            ShelfWidgetValueRow("Network", value: "Offline", systemImage: "wifi.slash")
        }
    }

    // MARK: Beside another widget

    private var split: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let me = shownResult {
                HStack(spacing: DroppySpacing.xsm) {
                    VPNDot(me: me)
                    IPFigure(text: me.ip, size: metrics.figureTextSize)
                }
                Text(splitCaption(me))
                    .droppyWidgetText(.caption)
                    .lineLimit(1)
            } else if let address = droplet.localNetwork?.address {
                IPFigure(text: address, size: metrics.figureTextSize)
                Text(droplet.lookupsOn ? "Local · \(droplet.lastError?.message ?? "looking up public IP…")" : "Local IP · public IP is off")
                    .droppyWidgetText(.caption)
                    .lineLimit(1)
            } else {
                Text("Offline")
                    .droppyWidgetText(.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func splitCaption(_ me: LiteMe) -> String {
        if let stale = droplet.staleNote { return stale }
        if let local = droplet.localNetwork?.address { return "\(LiteText.chip(me)) · Local \(local)" }
        return LiteText.chip(me)
    }
}

/// An address in the readout's type (rounded semibold, monospaced digits),
/// shrinking further than the readout does so a long IPv6 address still fits.
private struct IPFigure: View {
    let text: String
    let size: CGFloat
    @Environment(\.dropletShelfWidgetTextColor) private var textColor
    @Environment(\.dropletWidgetLayout) private var layout

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(textColor ?? layout?.foreground ?? AdaptiveColors.notchSurfacePrimaryText)
            .lineLimit(1)
            .minimumScaleFactor(text.contains(":") ? 0.35 : 0.6)
            .contentTransition(.numericText())
            .textSelection(.enabled)
    }
}
