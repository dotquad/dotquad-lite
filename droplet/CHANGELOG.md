## [1.0.0] - 2026-11-25

- The My IP shelf widget, in Droppy's own widget layout: your public IP with its country's flag, where it appears to be, the network's owner and ASN, and a VPN, Hosting or No VPN chip; a dotted world map with a pin where it appears; and your Mac's local IP, router and DNS servers.
- A Command Center tile with your IP as its title, and the map, the public and the local details inside.
- `my_public_ip`, `am_i_on_vpn` and `my_local_network` tools for AI apps, through Droppy's MCP server.
- Alerts, off until you turn them on: when your public IP changes, when your VPN turns on or off, and when your local IP changes. The VPN alert reads the Mac's own tunnel, so it works for any VPN that carries all traffic. Turning a VPN on or off, or switching servers, checks your public IP again within seconds, and the VPN alert says the new IP. Shown as a HUD in the island or as a notification, as you choose, using the other when Droppy can't show the one you picked, with a test button in settings.
- A VPN live activity, off until you turn it on: while your VPN is on, a shield and the country your IP appears in stay in the island.
- No internet, off until you turn it on: an alert when you're connected but nothing loads or a network wants a sign-in, Back online when it returns, and a live activity while it's out. Plain offline is left to Droppy's own No internet HUD.
- Look up an IP, domain or link on dotquad.app from Dotquad Lite's settings page.
- Public lookups are off until you turn them on, and ask dotquad.app only while the widget or tile is on screen, at most once every 5 minutes. Local details are read from your Mac and never sent.
