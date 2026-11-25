//
//  SettingsPane.swift
//  DotquadLite
//
//  Dotquad Lite's page in Droppy's Settings:
//
//  - Look up on dotquad.app: a field and buttons that open the website
//    tools with the input filled in. First, because a search result opens
//    the page at its top. Each tool has a search entry, so typing "Grade a
//    domain" in Droppy's search finds it. Nothing about the input is shown
//    here or sent anywhere but the browser.
//  - The opt-in switch and a link to dotquad.app.
//  - Alerts, as a HUD or a notification: when the public IP changes, when the VPN turns on or
//    off, and when the local IP changes. All off until turned on.
//  - The privacy note.
//
//  Droppy draws the page header (icon, name, summary), so this doesn't
//  repeat it. Buttons are native macOS ones, as Settings pages use.
//

import SwiftUI
import DroppyKit

extension DotquadLiteDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(DotquadLiteSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Look up on dotquad.app", keywords: ["ip", "domain", "lookup", "dns", "dotquad"]),
            SettingsSearchEntry(title: "Grade a domain", keywords: ["domain", "check", "email", "tls", "dns", "dotquad"]),
            SettingsSearchEntry(title: "Is this link safe?", keywords: ["link", "url", "phishing", "safe", "dotquad"]),
            SettingsSearchEntry(title: "Run a network checkup", keywords: ["network", "checkup", "dns", "ipv6", "dotquad"]),
            SettingsSearchEntry(title: "Test my VPN", keywords: ["vpn", "leak", "webrtc", "dns leak", "dotquad"]),
            SettingsSearchEntry(title: "Look up my public IP", keywords: ["ip", "vpn", "privacy", "dotquad"]),
            SettingsSearchEntry(title: "Alert when my public IP changes", keywords: ["alert", "notify", "ip change", "dotquad"]),
            SettingsSearchEntry(title: "Alert when my VPN turns on or off", keywords: ["alert", "notify", "vpn", "vpn off", "vpn drop", "kill switch", "dotquad"]),
            SettingsSearchEntry(title: "Alert when my local IP changes", keywords: ["alert", "notify", "local ip", "dhcp", "dotquad"]),
            SettingsSearchEntry(title: "Show my VPN as a live activity", keywords: ["live activity", "island", "vpn", "shield", "dotquad"]),
            SettingsSearchEntry(title: "Alert when I'm connected but there's no internet", keywords: ["no internet", "offline", "wifi", "captive", "sign in", "dotquad"]),
            SettingsSearchEntry(title: "Show No internet as a live activity", keywords: ["no internet", "offline", "live activity", "island", "dotquad"]),
            SettingsSearchEntry(title: "User guide", keywords: ["help", "guide", "how to", "troubleshooting", "dotquad"]),
            SettingsSearchEntry(title: "Show my VPN on the lock screen", keywords: ["lock screen", "locked", "vpn", "dotquad"]),
            SettingsSearchEntry(title: "Show alerts as", keywords: ["hud", "notification", "banner", "island", "alert", "dotquad"]),
        ]
    }
}

private struct DotquadLiteSettings: View {
    @ObservedObject var droplet: DotquadLiteDroplet
    @State private var input = ""

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var lookupURL: URL? { HandOff.lookup(trimmed) }
    private var gradeURL: URL? { HandOff.grade(trimmed) }
    private var linkURL: URL? { HandOff.linkCheck(trimmed) }

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Look up on dotquad.app")
            } content: {
                DropletSettingsCard {
                    DropletStackedRow(
                        title: "IP address, domain or link",
                        infoTip: "Opens the website tool in your browser with this filled in. Dotquad Lite shows no results itself."
                    ) {
                        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                            TextField(text: $input, prompt: Text("203.0.113.7, example.com or a link")) {
                                Text("IP address, domain or link")
                            }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .onSubmit(openBest)
                            HStack(spacing: DroppySpacing.sm) {
                                Button("Look Up") { open(lookupURL) }
                                    .disabled(lookupURL == nil)
                                    .keyboardShortcut(.defaultAction)
                                Button("Grade Domain") { open(gradeURL) }
                                    .disabled(gradeURL == nil)
                                Button("Check Link") { open(linkURL) }
                                    .disabled(linkURL == nil)
                            }
                            .buttonStyle(.bordered)
                            if !trimmed.isEmpty && lookupURL == nil && gradeURL == nil && linkURL == nil {
                                Text("Enter an IP address, a domain or a link.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            }
                        }
                    }
                    DropletControlRow(title: "Run a network checkup") {
                        Button("Open") { open(HandOff.checkup) }
                            .buttonStyle(.bordered)
                    }
                    DropletControlRow(title: "Test my VPN") {
                        Button("Open") { open(HandOff.vpnTest) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("My IP")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Look up my public IP",
                        subtitle: LiteText.consentNotice,
                        isOn: droplet.lookupsOnBinding
                    )
                    DropletControlRow(title: "Website") {
                        Button("Open dotquad.app") { droplet.openWebsite() }
                            .buttonStyle(.bordered)
                    }
                    DropletControlRow(title: "Help") {
                        Button("User Guide") { droplet.open(HandOff.guide()) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Alerts")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Alert when my public IP changes",
                        subtitle: droplet.lookupsOn
                            ? LiteText.publicAlertNote
                            : "Turn on \"Look up my public IP\" first.",
                        isOn: droplet.alertsPublicBinding
                    )
                    .disabled(!droplet.lookupsOn)
                    DropletToggleRow(
                        title: "Alert when my VPN turns on or off",
                        subtitle: droplet.lookupsOn ? LiteText.vpnAlertNote : LiteText.vpnAlertLocalNote,
                        isOn: droplet.alertsVPNBinding
                    )
                    DropletToggleRow(
                        title: "Alert when my local IP changes",
                        subtitle: LiteText.localAlertNote,
                        isOn: droplet.alertsLocalBinding
                    )
                    DropletToggleRow(
                        title: "Alert when I'm connected but there's no internet",
                        subtitle: LiteText.internetAlertNote,
                        isOn: droplet.alertsInternetBinding
                    )
                    DropletGroupedPickerRow(title: "Show alerts as") {
                        Picker("Show alerts as", selection: droplet.alertStyleBinding) {
                            ForEach(AlertStyle.allCases, id: \.self) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                    }
                    DropletStackedRow(title: "HUD or notification") {
                        Text(LiteText.alertStyleNote)
                            .font(.system(size: 12))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DropletControlRow(title: "Test the alerts") {
                        HStack(spacing: 8) {
                            Button("Help") { droplet.open(HandOff.guide("alerts")) }
                                .buttonStyle(.bordered)
                            Button("Show Test Alert") { droplet.showTestAlert() }
                                .buttonStyle(.bordered)
                        }
                    }
                    if let outcome = droplet.lastAlertOutcome {
                        DropletStackedRow(title: "Last alert") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LiteText.alertOutcome(outcome.rawValue, asChosen: outcome.rawValue == droplet.alertStyle.rawValue))
                                if let issue = droplet.lastNotificationIssue {
                                    Text(LiteText.notificationIssue(issue.rawValue))
                                }
                                if let issue = droplet.lastHUDIssue {
                                    Text(LiteText.hudIssue(issue.rawValue))
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !droplet.hudGranted && !droplet.bannersGranted {
                        DropletStackedRow(title: "Alerts are off") {
                            Text("Droppy has HUDs and notifications switched off for Dotquad Lite, so alerts can't show. Turn them on above, under this Droplet's permissions.")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Live activities")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show my VPN as a live activity",
                        subtitle: LiteText.activityNote,
                        isOn: droplet.activityOnBinding
                    )
                    DropletToggleRow(
                        title: "Show No internet as a live activity",
                        subtitle: LiteText.internetActivityNote,
                        isOn: droplet.internetActivityBinding
                    )
                    DropletControlRow(title: "How live activities work") {
                        Button("Help") { droplet.open(HandOff.guide("live-activities")) }
                            .buttonStyle(.bordered)
                    }
                    if droplet.activityOn || droplet.internetActivityOn {
                        DropletStackedRow(title: "Now") {
                            Text(LiteText.activityStatus(
                                active: droplet.activityTopic != nil,
                                published: droplet.activitySubject.value != nil,
                                seat: droplet.activitySeat
                            ))
                            .font(.system(size: 12))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Lock screen")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show my VPN on the lock screen",
                        subtitle: LiteText.lockScreenNote,
                        isOn: droplet.lockScreenOnBinding
                    )
                    DropletToggleRow(
                        title: "Include my IP",
                        subtitle: LiteText.lockScreenIPNote,
                        isOn: droplet.lockScreenIPBinding
                    )
                    .disabled(!droplet.lockScreenOn || !droplet.lookupsOn)
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Privacy")
            } content: {
                DropletSettingsCard {
                    DropletStackedRow(title: "What Dotquad Lite sends") {
                        Text(LiteText.privacyNote)
                            .font(.system(size: 12))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Return opens the tool that fits: an IP or domain opens the lookup,
    /// a link with a path or scheme opens the link checker.
    private func openBest() {
        if trimmed.contains("://") || trimmed.contains("/") {
            open(linkURL ?? lookupURL)
        } else {
            open(lookupURL ?? linkURL)
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        droplet.open(url)
    }
}
