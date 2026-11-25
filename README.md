# Dotquad Lite

A free [Droppy](https://getdroppy.app) Droplet that shows your Mac's public IP, where it appears to be, its network and whether it's a VPN. What it does and what it sends: [droplet/README.md](droplet/README.md).

## Layout

- `droplet/`: the Droplet, exactly as it goes into the Store repo at `droplets/dotquad-lite/`. Nothing else may be added there: the Store refuses tests, scripts and `Package.resolved`.
- `Package.swift` and `Tests/`: tests for the DroppyKit-free logic in `droplet/Sources/DotquadLite/Core` (decoding, `Retry-After`, the refresh rules, the text and the website links).

## Develop

```bash
swift test                      # the logic tests
cd droplet && swift build --target DotquadLite   # compile check only
```

The shipping bundle comes from DroppyKit's `droppykit build`, not `swift build`: a bare build folds in a second copy of DroppyKit and Droppy refuses the bundle. Run the harness and the checks with DroppyKit's CLI from a checkout of [droppykit](https://gitlab.com/droppyformac1/droppykit):

```bash
cd droplet
droppykit run          # the harness
droppykit validate     # manifest, lint and bundle checks
```

## Release

1. Raise `version` in `droplet/droplet.json` and `DotquadLiteDroplet.version` together, and add a `CHANGELOG.md` heading for it.
2. Copy `droplet/` to `droplets/dotquad-lite/` in a fork of the [Store repo](https://gitlab.com/droppyformac1/droplets) and open a merge request following its CONTRIBUTING.md. Leave out the icon: Droppy's designer adds `DotquadLite.icon/`.
