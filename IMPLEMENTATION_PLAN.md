# Implementation Plan — Disk Usage Widget (Tier 1, "Header widget")

Branch: `feature/disk-usage-widget` (off `origin/main`)

## Goal
Add a disk-usage row to the header summary area showing images / containers / volumes disk usage as
human-readable sizes, polled at **background** frequency (no stats-level cost). Read-only.

CLI: `container system df --format json`.

## Real CLI shape (verified against container v1.0.0) — IMPORTANT: top-level OBJECT, not array
```json
{
  "containers" : { "active" : 1, "reclaimable" : 0,         "sizeInBytes" : 324440064, "total" : 1 },
  "images"     : { "active" : 1, "reclaimable" : 240021504, "sizeInBytes" : 400912384, "total" : 2 },
  "volumes"    : { "active" : 0, "reclaimable" : 69390336,  "sizeInBytes" : 69390336,  "total" : 1 }
}
```
`ContainerJSONMapper.rootArray` expects a top-level array, so it WON'T work here — decode the object
directly with `JSONValue` accessors (`value.objectValue`, subscripting, `uint64Value`).

## Steps

### 1. Model — `Sources/ContainerCore/Models/ContainerModels.swift` (or new `DiskUsage.swift`)
Prefer a NEW file `Sources/ContainerCore/Models/DiskUsage.swift` to minimize merge surface:
```swift
public struct DiskUsageEntry: Equatable, Sendable {
    public let sizeBytes: UInt64?
    public let reclaimableBytes: UInt64?
    public let activeCount: Int?
    public let totalCount: Int?
    public init(...) { ... }
}
public struct DiskUsage: Equatable, Sendable {
    public let images: DiskUsageEntry
    public let containers: DiskUsageEntry
    public let volumes: DiskUsageEntry
    public init(...) { ... }
    public var totalSizeBytes: UInt64 { (images.sizeBytes ?? 0) + (containers.sizeBytes ?? 0) + (volumes.sizeBytes ?? 0) }
}
```
All Equatable + Sendable (mandatory per CLAUDE.md).

### 2. Mapper — `Sources/ContainerCore/Models/DiskUsageJSONMapper.swift` (new file)
`public enum DiskUsageJSONMapper { public static func diskUsage(from data: Data) throws -> DiskUsage }`.
- Decode `JSONValue` from data; require `value.objectValue` (throw `DecodingError.dataCorrupted` if not).
- For each of "images"/"containers"/"volumes" read the nested object's `sizeInBytes`, `reclaimable`,
  `active`, `total` via lenient accessors. Be defensive: missing section → empty `DiskUsageEntry()`.
- Try a couple key spellings for robustness (`sizeInBytes`/`size`, `reclaimable`/`reclaimableInBytes`)
  in the project's defensive style.

### 3. CLI client — `Sources/ContainerCore/Services/ContainerCLIClient.swift`
- Add to the `ContainerCLIClient` protocol:
  `func diskUsage() async throws -> DiskUsage`
- Implement in `ProcessContainerCLIClient`:
  `try await DiskUsageJSONMapper.diskUsage(from: runJSON(arguments: ["system", "df", "--format", "json"]))`

### 4. Snapshot — `Sources/ContainerCore/Models/ContainerModels.swift`
- Add `diskUsage: DiskUsage?` to `ContainerDashboardSnapshot` (default `nil`). Update the initializer
  (append `diskUsage` param with default; keep all existing params/defaults intact).

### 5. Polling — `Sources/ContainerCore/Services/PollingCoordinator.swift`
- Add `private var cachedDiskUsage: DiskUsage?`.
- Fetch df only at background-appropriate frequency. `system df` is cheap but not free; fetch it on
  EVERY refresh is unnecessary. Match the networks/volumes idiom but it's fine to refresh on each
  poll since both foreground (5s) and background (30s) are slow relative to df cost. Simplest correct
  choice: `cachedDiskUsage = (try? await client.diskUsage()) ?? cachedDiskUsage` on every refresh.
  (Document the choice in a comment. Do NOT gate it behind the stats signature — df should update when
  images/volumes change even if running containers don't.)
- Pass `diskUsage: cachedDiskUsage` into BOTH the success and catch-path snapshot initializers and
  into `staleSnapshot`.

### 6. View — `Sources/ContainerMenuBar/DashboardView.swift`
- Add a disk-usage row to the header summary area. Two acceptable placements:
  (a) extend the existing `summary` HStack with disk badges, or
  (b) add a second thin row under `summary` (a `Divider()` then an HStack) — preferred, so the
  existing container counts stay uncluttered.
- Show three labeled values: `Images <size>`, `Containers <size>`, `Volumes <size>` using
  `DisplayFormatters.bytes(...)`. Render only when `snapshot.diskUsage != nil`; otherwise hide the row.
- OPTIONAL polish (roadmap "small proportional bars"): a thin horizontal proportional bar per type
  sized by each section's share of `totalSizeBytes`. Keep it subtle (a few pt tall). Skip if it adds
  risk; the labeled sizes are the must-have.
- Reuse the existing `MetricBadge` style or a small local `DiskBadge` view for visual consistency.

### 7. Tests — `Sources/ContainerCoreSmokeTests/main.swift`
- `testParsesSystemDiskUsage()` using the real object JSON above as a string fixture; assert
  images.sizeBytes == 400912384, volumes.reclaimableBytes == 69390336, containers.totalCount == 1,
  and `totalSizeBytes` == sum.
- Register it in `SmokeTests.main()`.
- Add `diskUsage()` to `MockContainerCLIClient` (return a small fixed `DiskUsage`) so the suite compiles.
- Optionally assert the coordinator surfaces `diskUsage` in its snapshot after a refresh.

## Definition of done
- `swift build` clean. `swift run ContainerCoreSmokeTests` → all PASS (existing 8 + new).
- ContainerCore stays UI-free; new public types Equatable + Sendable.
- df poll does not add a stats-level (double-sample) cost; runs at normal poll cadence.
- Commit on `feature/disk-usage-widget`; do not push.
