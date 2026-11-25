//
//  SettingsPane.swift
//  DotquadLite
//
//  Dotquad Lite's page in Droppy's Settings:
//
//  - Look up on dotquad.app: how to use the Look Up widget, with buttons to
//    open it and change its shortcut. The field itself lives in the widget.
//  - The opt-in switch, a link to dotquad.app and the user guide.
//  - Alerts, as a HUD or a notification, and the test.
//  - Live activities, and the lock screen row.
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
            SettingsSearchEntry(title: "Open Look Up", keywords: ["look up", "lookup", "domain", "link", "checkup", "vpn test", "shortcut", "dotquad"]),
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

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Look up on dotquad.app")
            } content: {
                DropletSettingsCard {
                    DropletStackedRow(title: "The Look Up widget") {
                        Text(LiteText.lookUpNote)
                            .font(.system(size: 12))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DropletControlRow(title: "Look Up") {
                        HStack(spacing: 8) {
                            Button("Change Shortcut") { droplet.host?.workspace.openShortcuts() }
                                .buttonStyle(.bordered)
                            Button("Open Look Up") { droplet.showLookUp() }
                                .buttonStyle(.bordered)
                        }
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
}
