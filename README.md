h# ContainerMenuBar

A lightweight, read-only macOS menu bar monitor for Apple `container`.

The app uses the installed `container` CLI as its stable API boundary and reads JSON output from:

- `container list --all --format json`
- `container stats --format json --no-stream`
- `container inspect <id>`
- `container network list --format json`
- `container volume list --format json`
- `container system status`

It does not run a helper service and does not link the Apple `container` Swift package internals. Polling is intentionally conservative because `container stats --no-stream` performs two samples with a built-in delay.

## Build

```sh
swift build
swift run ContainerCoreSmokeTests
make package
open dist/ContainerMenuBar.app
```

If Swift reports an SDK/toolchain mismatch, align the active Xcode or Command Line Tools first:

```sh
xcode-select -p
swift --version
```

## Efficiency Defaults

- Popover closed: lightweight status/list polling every 30 seconds; stats are skipped unless the container set changes.
- Popover open: list and stats refresh every 5 seconds.
- Manual refresh is available in the UI.
- CLI calls are serialized so expensive stats reads cannot overlap.
