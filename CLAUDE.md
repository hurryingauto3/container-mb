# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A read-only macOS menu bar app that monitors Apple's `container` runtime. It shells out to the installed `container` CLI and parses its JSON/text output — it does **not** link Apple's `container` Swift package internals and does **not** run a background helper service. The CLI is treated as the stable API boundary; everything downstream defends against shape drift in that output.

## Commands

```sh
make build      # swift build
make test       # swift run ContainerCoreSmokeTests  (the only test suite)
make run        # swift run ContainerMenuBar          (launches the app)
make package    # Scripts/package-app.sh -> dist/ContainerMenuBar.app (release build + Info.plist)
make clean
```

Run a single test by editing `Sources/ContainerCoreSmokeTests/main.swift`: comment out unwanted `suite.run(...)` lines in `SmokeTests.main()`. There is no XCTest target and no per-test filter — the suite is a hand-rolled runner that prints `PASS`/`FAIL` and exits non-zero on any failure.

If `swift build` reports an SDK/toolchain mismatch, reconcile the active toolchain first (`xcode-select -p`, `swift --version`).

## Architecture

Two targets layered on a shared library, all defined in `Package.swift`:

- **ContainerCore** (library) — all logic and models. No AppKit/SwiftUI. This is what the tests exercise.
- **ContainerMenuBar** (executable) — thin AppKit/SwiftUI shell over ContainerCore.
- **ContainerCoreSmokeTests** (executable) — the test suite.

Data flow, outermost to innermost:

```
AppDelegate -> StatusBarController -> DashboardViewModel -> PollingCoordinator -> ContainerCLIClient -> ProcessRunner -> `container` CLI
                                                                  |                      |
                                                          ContainerJSONMapper  <----  JSON/text output
```

- **ProcessRunner** (`Services/ProcessRunner.swift`) — runs a subprocess on a background queue with a hard timeout (SIGTERM, then SIGKILL after 1s). Hidden behind the `ProcessRunning` protocol so tests inject mocks.
- **ProcessContainerCLIClient** (`Services/ContainerCLIClient.swift`) — knows the exact `container` subcommands (`list --all --format json`, `stats --format json --no-stream`, `inspect`, `network list`, `volume list`, `system status`, `--version`). Locates the binary by probing `/usr/local/bin`, `/opt/homebrew/bin`, `/usr/bin`, then `PATH`. Conforms to the `ContainerCLIClient` protocol — the seam where the `MockContainerCLIClient` in the test file substitutes.
- **PollingCoordinator** (`Services/PollingCoordinator.swift`) — an `actor` that caches the last snapshot and decides what to refresh. **The efficiency rules live here.** `stats` is the expensive call (`--no-stream` samples twice with a built-in delay), so it is skipped on background polls unless the container set's signature changed (`id:state` joined and sorted) or a refresh is forced. CPU percent is *computed* by `enrichCPUPercent` from the delta between two `cpuUsageUsec` samples — the CLI does not report it directly. On any error it returns the previous snapshot marked `isStale` with an `errorMessage` rather than throwing.
- **DashboardViewModel** (`ViewModels/DashboardViewModel.swift`) — `@MainActor ObservableObject` driving the UI. Owns the poll loop `Task`. Switches between `.foreground` (popover open, 5s) and `.background` (closed, 30s) modes via `setPopoverVisible`. `PollingConfiguration` holds the two intervals.

### JSON parsing strategy (important)

The CLI's JSON shape is treated as untrusted and drift-prone. Two pieces absorb that:

- **JSONValue** (`Models/JSONValue.swift`) — a dynamic JSON enum with lenient accessors (`stringValue` coerces numbers/bools, `uint64Value` parses strings), key subscripting, `value(at: [path])`, and `deepValues(named:)` for recursive key search.
- **ContainerJSONMapper** (`Models/ContainerJSONMapper.swift`) — maps `JSONValue` into the strongly-typed domain models (`Models/ContainerModels.swift`). It tries multiple key spellings for nearly every field (e.g. `proto`/`protocol`, `numProcesses`/`processCount`, `memoryInBytes`/`memory`) and falls back to deep search when a key isn't where expected. The full raw `JSONValue` is retained on `ContainerSummary.raw`.

When the CLI output format changes, fix it in **ContainerJSONMapper** (add a key alias or fallback) and add a fixture-based case to the smoke tests — don't push parsing concerns up into the view layer.

## Conventions

- ContainerCore must stay UI-free (no AppKit/SwiftUI imports) so it remains testable headless.
- All public model/state types are `Equatable` + `Sendable`; cross-actor types (`ContainerCLIClient`, `ProcessRunning`) are `Sendable` protocols. Preserve this when adding types — the concurrency model depends on it.
- New CLI interactions go through the `ContainerCLIClient` protocol so they can be mocked; new subprocess behavior goes through `ProcessRunning`.
- Tests are fixture-driven: paste representative CLI JSON as a string literal and assert the mapped model (see `testParsesManagedContainerShape`).
