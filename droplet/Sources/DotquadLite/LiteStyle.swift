//
//  LiteStyle.swift
//  DotquadLite
//
//  Dotquad's two status colors, from the brand's design language: Signal teal
//  for the accent and "no VPN", Flag amber for VPN, proxy and hosting. Each
//  has a light and a dark value, picked by the surface's appearance.
//

import SwiftUI
import AppKit
import DroppyKit

enum LiteColor {
    /// #0F766E on light, #2DD4BF on dark.
    static let signal = dynamic(light: 0x0F766E, dark: 0x2DD4BF)
    /// #B45309 on light, #F59E0B on dark.
    static let flag = dynamic(light: 0xB45309, dark: 0xF59E0B)

    static func badge(_ badge: LiteBadge?) -> Color {
        badge == nil ? signal : flag
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The VPN dot: Flag amber on a VPN or hosting address, Signal teal otherwise,
/// hollow while the VPN status is unknown.
struct VPNDot: View {
    let me: LiteMe
    var size: CGFloat = 8

    var body: some View {
        let badge = LiteText.badge(me)
        Group {
            if me.vpn == nil && me.hosting == nil {
                Circle().strokeBorder(AdaptiveColors.notchSurfaceTertiaryText, lineWidth: 1.5)
            } else {
                Circle().fill(LiteColor.badge(badge))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(LiteText.vpnStatus(me))
    }
}

/// "VPN", "Hosting" or "No VPN" on a tinted capsule.
struct StatusChip: View {
    let me: LiteMe
    var size: CGFloat = 11

    var body: some View {
        let tint = LiteColor.badge(LiteText.badge(me))
        Text(LiteText.chip(me))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.18)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

/// What a copy button copies.
enum CopyTarget {
    case publicIP
    case localIP

    var label: String {
        switch self {
        case .publicIP: return "Copy IP"
        case .localIP: return "Copy local IP"
        }
    }
}

/// Copy, morphing to a checkmark for 1.6 s, as the brand's motion table says.
/// With no diameter it takes the shelf's own wash, at the mount's size.
struct CopyButton: View {
    @ObservedObject var droplet: DotquadLiteDroplet
    var target: CopyTarget = .publicIP
    var diameter: CGFloat? = nil
    var usesAdaptiveForegrounds: Bool = true
    var tone: DroppyWashTone = .neutral
    @State private var copied = false

    var body: some View {
        let button = Button {
            let ok = target == .publicIP ? droplet.copyIP() : droplet.copyLocalIP()
            guard ok else { return }
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(!available || !droplet.copyGranted)
        .help(droplet.copyGranted ? target.label : "Clipboard access is off for Dotquad Lite in Droppy Settings.")
        .accessibilityLabel(copied ? "Copied" : target.label)

        if let diameter {
            button.buttonStyle(
                DroppyWashCircleButtonStyle(diameter: diameter, tone: tone, usesAdaptiveForegrounds: usesAdaptiveForegrounds)
            )
        } else {
            button.buttonStyle(DroppyWashButtonStyle(tone: tone))
        }
    }

    private var symbol: String {
        target == .publicIP ? "doc.on.doc" : "doc.on.clipboard"
    }

    private var available: Bool {
        target == .publicIP ? droplet.result != nil : droplet.localNetwork?.address != nil
    }
}

/// A dot-matrix world map with a pin where the public IP appears: Signal
/// teal for an ordinary address, Flag amber for a VPN or hosting address.
/// No pin while there's no answer or the data has no city. Drawn in one
/// Canvas, so it costs one layer however many dots it has.
struct DotMap: View {
    let me: LiteMe?
    /// The land dots' ink.
    var ink: Color
    var inkOpacity: Double = 0.22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Canvas { context, canvas in
                    let cell = CGSize(
                        width: canvas.width / CGFloat(WorldDots.columns),
                        height: canvas.height / CGFloat(WorldDots.rows.count)
                    )
                    let radius = min(cell.width, cell.height) * 0.34
                    var land = Path()
                    for row in WorldDots.rows.indices {
                        for column in 0..<WorldDots.columns where WorldDots.isLand(column: column, row: row) {
                            let center = CGPoint(
                                x: (CGFloat(column) + 0.5) * cell.width,
                                y: (CGFloat(row) + 0.5) * cell.height
                            )
                            land.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                        }
                    }
                    context.fill(land, with: .color(ink.opacity(inkOpacity)))
                }
                if let pin {
                    Pin(tint: tint, animates: !reduceMotion, place: "\(pin.x),\(pin.y)")
                        .position(x: pin.x * size.width, y: pin.y * size.height)
                }
            }
        }
        .aspectRatio(CGFloat(WorldDots.columns) / CGFloat(WorldDots.rows.count), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(me.flatMap { LiteText.place($0) }.map { "Map: \($0)" } ?? "World map")
    }

    private var pin: (x: Double, y: Double)? {
        guard let latitude = me?.latitude, let longitude = me?.longitude else { return nil }
        return WorldDots.point(latitude: latitude, longitude: longitude)
    }

    private var tint: Color {
        me.map { LiteColor.badge(LiteText.badge($0)) } ?? LiteColor.signal
    }
}

/// The map's pin: a solid dot in a soft halo. The halo pulses three times
/// when it appears or the place changes, then rests.
private struct Pin: View {
    let tint: Color
    let animates: Bool
    let place: String
    @State private var shown = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 18, height: 18)
                .phaseAnimator([1.0, 1.35, 0.9, 1.35, 0.9, 1.35, 1.0], trigger: shown) { halo, scale in
                    halo.scaleEffect(scale).opacity(scale > 1 ? 0.55 : 1)
                } animation: { _ in
                    animates ? .easeInOut(duration: 0.45) : nil
                }
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
        }
        .frame(width: 18, height: 18)
        .onAppear { if animates { shown += 1 } }
        .onChange(of: place) { if animates { shown += 1 } }
        .accessibilityHidden(true)
    }
}
