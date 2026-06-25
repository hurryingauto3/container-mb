# Implementation Plan — Detail Panels (Tier 1, "Panel extension" ×3)

Branch: `feature/detail-panels` (off `origin/main`)

Three panel-extension features that all enrich existing detail panels with lazy, on-demand
CLI calls. Read-only throughout.

1. **Container Logs Viewer** — `logs <id> -n 200`, `logs <id> --boot`
2. **Volume Detail Inspect** — `volume inspect <name>`
3. **Network Detail Inspect** — `network inspect <name>`

## Real CLI shapes (verified against container v1.0.0)

### logs — PLAIN TEXT (not JSON)
`container logs <id> -n 200` → newline-separated log lines on stdout.
`container logs <id> --boot` → VM/kernel init lines, e.g. `[    0.069837] random: crng init done`.
Usage: `container logs [--boot] [--follow] [-n <n>] <container-id>`. Do NOT pass `--follow`
(that is Tier 3 streaming; out of scope).

### volume inspect — array
```json
[{ "id": "testvol",
   "configuration": {
     "driver": "local", "format": "ext4", "name": "testvol",
     "sizeInBytes": 549755813888,
     "source": "/Users/.../com.apple.container/volumes/testvol/volume.img",
     "creationDate": "2026-06-24T02:04:11Z",
     "labels": {}, "options": {}
   } }]
```
Inspect adds (vs list): full `source` mount path, `labels`, `options`, `creationDate`.

### network inspect — array
```json
[{ "id": "default",
   "configuration": { "mode": "nat", "name": "default", "plugin": "container-network-vmnet",
     "creationDate": "2026-06-24T01:57:25Z", "labels": {"com.apple.container.resource.role":"builtin"}, "options": {} },
   "status": { "ipv4Gateway": "192.168.64.1", "ipv4Subnet": "192.168.64.0/24", "ipv6Subnet": "fd37:5540:3aa9:5b60::/64" } }]
```
Inspect adds (vs list): `ipv6Subnet`, `labels`, `creationDate`, `options`.
NOTE: `network inspect` does **not** list attached containers. The "attached containers"
deep-link from the roadmap is derivable client-side by filtering `snapshot.containers` whose
`networks` contains this network name — implement that derivation in the ViewModel/View, not a CLI call.

## Existing patterns to reuse
- `ResourceSummary` already has `attributes: [ResourceAttribute]` and `detail: String?`, and
  `ContainerJSONMapper.resourceAttributes(from:)` already probes driver/format/size/source (volumes)
  and mode/subnet/gateway/plugin (networks). Inspect just adds MORE attributes (labels, options,
  ipv6 subnet, created, full source). Reuse `resourceAttributes` / add a second enrich step.
- Lazy-on-selection precedent: container `inspect` exists as `inspectContainers(ids:)` in the client,
  though PollingCoordinator does not currently call it on selection. You will add selection-driven
  lazy inspect for volumes/networks.

## Steps

### 1. CLI client — `Sources/ContainerCore/Services/ContainerCLIClient.swift`
Add to the `ContainerCLIClient` protocol and implement in `ProcessContainerCLIClient`:
- `func containerLogs(id: String, lines: Int, boot: Bool) async throws -> String`
  → builds args `["logs", "-n", String(lines), id]`, plus `--boot` when boot==true (place `--boot`
  before the id: `["logs", "--boot", "-n", String(lines), id]`). Return `result.stdoutString`.
  Use a slightly larger timeout (e.g. `max(timeout, 8)`). Output is text — add a `runText(...)`
  private helper that mirrors `runJSON` but returns `result.stdoutString` (and still throws on
  non-zero exit). Do not JSON-decode.
- `func inspectVolume(name: String) async throws -> ResourceSummary?`
  → `ContainerJSONMapper.resources(from: runJSON(arguments: ["volume", "inspect", name])).first`
- `func inspectNetwork(name: String) async throws -> ResourceSummary?`
  → `["network", "inspect", name]`, same mapping, `.first`.

### 2. Mapper — `Sources/ContainerCore/Models/ContainerJSONMapper.swift`
- Extend `resourceAttributes(from:)` so it also surfaces the inspect-only fields when present:
  add probes for `Created` (`["configuration","creationDate"]`, format relative or ISO — keep as
  string), and render `labels`/`options` (objects). For label/option objects, append one
  `ResourceAttribute` per key as `label: key, value: stringValue` OR a single joined attribute —
  pick the simpler readable option; keep ordering stable (sorted keys) so tests are deterministic.
  Add an ipv6 subnet probe: `add("IPv6 Subnet", paths: [["status","ipv6Subnet"]])`.
- IMPORTANT: the existing list-based `testParsesLiveResourceDetail` smoke test asserts the EXACT
  attribute array for list responses. If you add attributes that also appear for the LIST shape,
  that test will break. The inspect fixtures include labels/options/created that the list fixtures
  do NOT, so only add attributes that are absent from the list fixture — verify the existing test
  still passes. If a new probe would fire on the list fixture, gate it so it doesn't, or update the
  existing test fixture/expectation deliberately and note why.

### 3. Snapshot / caches — keep list data as the base
Volumes/networks lists still come from `listVolumes`/`listNetworks`. The inspect result enriches a
single selected item on demand. Store enriched detail in the ViewModel (not the polled snapshot),
so background polls don't clobber it. See step 5.

### 4. (No PollingCoordinator change required for inspect) — keep polling as-is.
Inspect/logs are user-driven, fetched directly via the client from the ViewModel. Do not add them
to the poll loop (matches the "lazy on selection, no polling overhead" requirement). If you find a
clean seam to route them through the coordinator, that's acceptable, but the ViewModel-direct path
is simplest and lowest-risk. Ensure the client is reachable from the ViewModel (today the ViewModel
only holds the coordinator). Add a stored `client` reference, OR add passthrough methods on
PollingCoordinator (`func inspectVolume(...)`, `func containerLogs(...)`) that forward to the client.
Prefer adding passthrough methods on the actor (keeps the single client owner). Implement those
forwards on PollingCoordinator.

### 5. ViewModel — `Sources/ContainerCore/ViewModels/DashboardViewModel.swift`
- Add `@Published public var selectedVolumeID: String?` and `selectedNetworkID: String?`.
- Add `@Published public private(set) var volumeDetail: ResourceSummary?` and `networkDetail: ResourceSummary?`
  (the enriched inspect result for the current selection; cleared when selection changes).
- Add `func selectVolume(_ id: String?)` / `selectNetwork(_ id: String?)` that set the id, clear the
  stale detail, and kick a Task to fetch inspect via the coordinator passthrough; assign on success.
- Logs state: add
  `@Published public private(set) var containerLogs: String?`,
  `@Published public var logsShowBoot: Bool = false`,
  `@Published public private(set) var isLoadingLogs: Bool`.
  Add `func loadLogs(for containerID: String, boot: Bool)` (async Task) calling the coordinator
  passthrough `containerLogs(id:lines:boot:)` with lines=200; store result. Clear logs when the
  selected container changes. Toggling `logsShowBoot` re-fetches.
- For network attached-containers: add `func containers(attachedTo networkName: String) -> [ContainerSummary]`
  filtering `snapshot.containers` by `networks.contains(networkName)`.

### 6. Views

#### Logs — `Sources/ContainerMenuBar/ContainerViews.swift`
Add a collapsible "Logs" section to `ContainerDetailView`, BELOW the stats grid (a
`DisclosureGroup`, collapsed by default; fetch on first expand). Contents:
- A header row: title "Logs", a `--boot` Toggle (bound to viewModel.logsShowBoot), a "Copy all"
  button (NSPasteboard, reuse the CopyButton pattern), and a small ProgressView while loading.
- Monospaced, selectable, horizontally scrollable text (`ScrollView([.vertical,.horizontal])` with a
  `Text(logs).font(.system(.caption, design: .monospaced)).textSelection(.enabled)`), bounded height
  (e.g. 220pt). Show "No logs" when empty, an error string on failure.
Because `ContainerDetailView` currently takes only `container`/`stats`, you'll need access to the
view model here. Pass the `DashboardViewModel` (as `@ObservedObject`) into `ContainerDetailView`, or
pass closures + the logs state. Passing the view model is simplest and matches how DashboardView
already holds it. Update the call site in `DashboardView.containersContent` accordingly.

#### Volume / Network detail — `Sources/ContainerMenuBar/ContainerViews.swift`
The Volumes/Networks tabs currently render a flat `ResourceListView` (cards, no selection). Add a
master-detail (or expand-in-place) so selecting a volume/network triggers inspect and shows the
enriched attributes. Minimal approach that fits the existing card UI: make `ResourceCardView`
selectable; on tap call `viewModel.selectVolume(id)` / `selectNetwork(id)`; render the enriched
`volumeDetail`/`networkDetail` attributes inside the selected card (fall back to the list-level
attributes until inspect returns). For networks, also render an "Attached containers" subsection
listing `viewModel.containers(attachedTo: name)` — each row tappable to switch to the Containers
tab and select that container (`viewModel.selectedSection = .containers; viewModel.select(containerID:)`).
Keep `ResourceListView`/`ResourceCardView` changes additive; update `DashboardView` call sites to
pass the view model.

### 7. Tests — `Sources/ContainerCoreSmokeTests/main.swift`
- `testParsesVolumeInspectDetail()` — feed the volume-inspect fixture; assert the enriched
  attributes include Driver/Format/Size/Source AND the inspect-only Created/labels (whatever you map).
- `testParsesNetworkInspectDetail()` — feed the network-inspect fixture; assert IPv6 Subnet + labels
  appear in addition to Mode/Subnet/Gateway/Plugin.
- Confirm the EXISTING `testParsesLiveResourceDetail` still passes unchanged (or update it deliberately
  with a comment if you intentionally changed list attribute output).
- Add the three new methods to `MockContainerCLIClient` (containerLogs, inspectVolume, inspectNetwork)
  so the suite compiles. Optionally add an actor test that the coordinator passthrough returns logs.
- Register new tests in `SmokeTests.main()`.

## Definition of done
- `swift build` clean. `swift run ContainerCoreSmokeTests` → all PASS (existing 8 + new).
- Existing `testParsesLiveResourceDetail` still green.
- ContainerCore stays UI-free; new public types Equatable + Sendable.
- Logs are bounded (200 lines), no `--follow`, no long-running subprocess.
- Commit on `feature/detail-panels`; do not push.
