# Dotquad Lite

Shows your Mac's public IP on Droppy's shelf: where it appears to be, the network that owns it, and whether it's a VPN or hosting address. Beside it, your Mac's side of the network: the local IP, the router and the DNS servers. Everything else opens on [dotquad.app](https://dotquad.app).

## What it shows

- **My IP widget.** On the left, your public IP, the country's flag and where it appears to be, a VPN, Hosting or No VPN chip, and the network's owner and ASN. In the middle, a dotted world map with a pin where your IP appears: teal for an ordinary address, amber for a VPN or hosting address. On the right, your Mac's interface (Wi-Fi or Ethernet) with its local IP, the router and the DNS servers. The header copies the public IP, opens Look Up and opens the full lookup on dotquad.app. Beside another widget it shows the IP, the VPN dot and the local IP.
- **Command Center tile.** Your IP as the tile's title, with a shield when it's a VPN. Press it for the map, the public IP and its status, then the local IP, the router and the DNS servers, each copyable.
- **Alerts.** Two switches in Dotquad Lite's settings, both off until you turn them on. One shows a banner when your public IP changes, or your VPN turns off or on; the other when your Mac's local IP changes. Each banner has Copy and Open. They're Droppy's own banners, so Focus and Droppy's notification settings apply.
- **Look up on dotquad.app.** At the top of Dotquad Lite's settings page: type an IP, a domain or a link, then Look Up, Grade Domain or Check Link opens that tool on dotquad.app with it filled in. The network checkup and the VPN test are one click below. Search Droppy's Settings for "Grade a domain" or "Test my VPN" to get there, or press Look Up… on the tile. Nothing is looked up inside Droppy: these only open your browser.
- **Tools for AI apps.** With Droppy's MCP server on, AI apps can call `my_public_ip`, `am_i_on_vpn` and `my_local_network`. They're answered from your Mac, so "my IP" is yours, not the AI app's server. `my_local_network` works with lookups off: it reads the Mac and sends nothing.

The location is where Dotquad's IP data places the address, which is what websites act on. Other sites use other data and may place it differently. With a VPN on, it's the VPN's location.

The VPN dot is amber on a VPN or hosting address and teal otherwise. It's hollow while dotquad.app's privacy detection lists are still loading.

## Turning it on

Dotquad Lite sends nothing until you agree. The local half of the widget (local IP, router, DNS) works from the start, because it's read from your Mac and never sent. The first time you open the widget, it says what it sends and offers **Turn On**. You can switch it off anytime in Droppy Settings, Dotquad Lite, "Look up my public IP". Switching it off also forgets the last answer.

## Privacy

- **What's sent:** one request to `https://api.dotquad.app/lite/me`, which answers with your IP's place to about 11 km (0.1°) for the map, never finer than the city it names. dotquad.app sees your public IP, as any website you visit does, and a `User-Agent: DotquadLite/<version>` header used to count requests. No account, key, cookie or device ID.
- **When:** only while the widget or the tile is on screen, at most once every 5 minutes, plus once after your network changes (after a random wait of up to 30 seconds). With public IP alerts on, that after-a-change request goes out even when the widget is closed, and once when Droppy starts. An AI app's tool call also asks, using the same 5-minute limit.
- **What's never sent:** your local IP, router and DNS servers. They're read from your Mac to show them, and only an AI app you allowed in Droppy can ask for them.
- **What's kept:** nothing about you, on your Mac or on the server, beyond a count of requests. The last answer lives in memory only and is gone when Droppy quits.

## Permissions

- `network-client`: to ask dotquad.app.
- `menu-bar`: for the Command Center tile.
- `clipboard-write`: for Copy.
- `notch-banner`: for the alerts, if you turn them on.

## License

MIT for the source code. The Dotquad name, logo and icon aren't covered; see [NOTICE.md](NOTICE.md).
