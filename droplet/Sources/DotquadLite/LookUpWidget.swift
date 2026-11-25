//
//  LookUpWidget.swift
//  DotquadLite
//
//  The Look Up widget: one field for an IP, a domain or a link, and buttons
//  for the website's tools. Everything opens on dotquad.app in the browser;
//  nothing is shown in the notch, so Lite never does the Mac app's Pro job.
//
//  Alone on the shelf:
//
//      Look Up                                   Network Checkup  VPN Test
//      [ 203.0.113.7, example.com or a link                            ]
//      Look Up   Grade Domain   Check Link
//
//  Beside another widget: the field and a Look Up button.
//
//  Return opens the best tool for what was typed (HandOff.best). A global
//  shortcut, set on Droppy's Shortcuts page, opens the shelf on this widget
//  with the cursor in the field.
//

import SwiftUI
import DroppyKit

enum LookUpSize {
    static let singleWidth: CGFloat = 560
    static let singleHeight: CGFloat = 100
    static let splitWidth: CGFloat = 210
    static let splitHeight: CGFloat = 76
}

extension DotquadLiteDroplet {
    static let lookUpWidgetID: ShelfWidgetID = "look-up"
    static let lookUpShortcutID = "look-up"

    var lookUpDescriptor: ShelfWidgetDescriptor {
        ShelfWidgetDescriptor(
            id: Self.lookUpWidgetID,
            title: "Look Up",
            systemImage: "magnifyingglass",
            layoutTraits: ShelfWidgetLayoutTraits(
                single: ShelfWidgetModeSize(width: LookUpSize.singleWidth, contentHeight: LookUpSize.singleHeight),
                split: ShelfWidgetModeSize(width: LookUpSize.splitWidth, contentHeight: LookUpSize.splitHeight),
                header: .standard
            ),
            focusPolicy: .keyboardFocusable,
            searchKeywords: [
                "look up", "lookup", "ip", "domain", "dns", "grade", "report card", "link", "phishing",
                "checkup", "vpn test", "leak", "dotquad",
            ]
        )
    }

    /// Opens the shelf on the Look Up widget. From the shortcut, the tile and
    /// the My IP widget. Falls back to dotquad.app when Droppy refuses.
    func showLookUp() {
        guard let host else { return }
        if !host.shelf.open(revealing: Self.lookUpWidgetID) {
            open(HandOff.home)
        }
    }

    /// The shortcut, registered on activate. Droppy keeps the user's binding
    /// and drops the default when it clashes with another.
    func registerLookUpShortcut() {
        host?.shortcuts.register(
            id: Self.lookUpShortcutID,
            title: "Look up on dotquad.app",
            defaultShortcut: DropletKeyboardShortcut(
                keyCode: 2, // D
                modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue
            ),
            handler: { [weak self] in self?.showLookUp() }
        )
    }
}

struct LookUpWidget: View {
    @ObservedObject var droplet: DotquadLiteDroplet
    @Environment(\.dropletWidgetLayout) private var layout
    @State private var input = ""

    private var isSplit: Bool { layout?.isSplit ?? false }
    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var best: URL? { HandOff.best(trimmed) }
    private var lookupURL: URL? { HandOff.lookup(trimmed) }
    private var gradeURL: URL? { HandOff.grade(trimmed) }
    private var linkURL: URL? { HandOff.linkCheck(trimmed) }

    var body: some View {
        ShelfWidgetScaffold("Look Up", systemImage: "magnifyingglass") {
            if !isSplit {
                Button("Network Checkup", systemImage: "stethoscope") { droplet.open(HandOff.checkup) }
                    .help("Run a network checkup on dotquad.app")
                Button("VPN Test", systemImage: "lock.shield") { droplet.open(HandOff.vpnTest) }
                    .help("Test your VPN for leaks on dotquad.app")
            }
        } content: {
            DropletWidgetComposition {
                single
            } split: {
                split
            }
        }
        .onAppear {
            guard !(layout?.isPreview ?? false) else { return }
            droplet.host?.shelf.requestKeyboardFocus()
        }
    }

    private var field: some View {
        DroppyShelfTextField("IP address, domain or link", text: $input) { go(best) }
            .autocorrectionDisabled()
            .help("An IP opens the IP lookup, a domain its report card, a link the link checker")
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            field
            HStack(spacing: DroppySpacing.sm) {
                Button("Look Up", systemImage: "magnifyingglass") { go(lookupURL) }
                    .buttonStyle(DroppyWashButtonStyle(tone: .accent(LiteColor.signal)))
                    .disabled(lookupURL == nil)
                Button("Grade Domain", systemImage: "checkmark.seal") { go(gradeURL) }
                    .disabled(gradeURL == nil)
                Button("Check Link", systemImage: "link") { go(linkURL) }
                    .disabled(linkURL == nil)
                Spacer(minLength: 0)
                if !trimmed.isEmpty && best == nil {
                    Text("Enter an IP, a domain or a link")
                        .droppyWidgetText(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    private var split: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            field
            Button("Look Up", systemImage: "magnifyingglass") { go(best) }
                .buttonStyle(DroppyWashButtonStyle(tone: .accent(LiteColor.signal)))
                .disabled(best == nil)
        }
    }

    private func go(_ url: URL?) {
        guard let url else { return }
        droplet.open(url)
        input = ""
    }
}
