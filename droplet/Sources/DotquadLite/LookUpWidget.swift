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
    static let singleHeight: CGFloat = 112
    static let splitWidth: CGFloat = 210
    static let splitHeight: CGFloat = 96
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
            // Row-sized pills (28), not the 34 a lone control gets. When the
            // labels don't fit the width Droppy gives, the icons stay.
            ViewThatFits(in: .horizontal) {
                toolRow(labelled: true)
                toolRow(labelled: false)
            }
            .droppyWashControlSize(28)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func toolRow(labelled: Bool) -> some View {
        HStack(spacing: DroppySpacing.sm) {
            tool("Look Up", "magnifyingglass", lookupURL, labelled: labelled)
                .buttonStyle(DroppyWashButtonStyle(tone: .accent(LiteColor.signal), size: 28))
            tool("Grade Domain", "checkmark.seal", gradeURL, labelled: labelled)
            tool("Check Link", "link", linkURL, labelled: labelled)
            Spacer(minLength: 0)
            if labelled && !trimmed.isEmpty && best == nil {
                Text("Enter an IP, a domain or a link")
                    .droppyWidgetText(.caption)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func tool(_ title: String, _ symbol: String, _ url: URL?, labelled: Bool) -> some View {
        Button { go(url) } label: {
            if labelled {
                Label(title, systemImage: symbol).lineLimit(1).fixedSize()
            } else {
                Image(systemName: symbol)
            }
        }
        .disabled(url == nil)
        .help(title)
        .accessibilityLabel(title)
    }

    /// A narrow card with far more height than the shelf gives (a Command
    /// Center card) also gets the checkup and VPN test, which the header
    /// has no room for there.
    private var isRoomySplit: Bool {
        (layout?.contentSize.height ?? 0) > LookUpSize.splitHeight * 1.3
    }

    private var split: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            field
            Button("Look Up", systemImage: "magnifyingglass") { go(best) }
                .buttonStyle(DroppyWashButtonStyle(tone: .accent(LiteColor.signal), size: 28))
                .disabled(best == nil)
            if isRoomySplit {
                HStack(spacing: DroppySpacing.sm) {
                    tool("Checkup", "stethoscope", HandOff.checkup, labelled: true)
                    tool("VPN Test", "lock.shield", HandOff.vpnTest, labelled: true)
                }
                .droppyWashControlSize(28)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func go(_ url: URL?) {
        guard let url else { return }
        droplet.open(url)
        input = ""
    }
}
