# Implementation Plan — Images Tab (Tier 1, "New tab")

Branch: `feature/images-tab` (off `origin/main`)

## Goal
Add a fourth segment — **Images** — to the existing Containers / Volumes / Networks
control, with a master-detail layout that mirrors the Containers tab. Read-only.

CLI: `container image list --format json` (and optionally `container image inspect <name>`).

## Real CLI shape (verified against container v1.0.0)
`image list --format json` returns a **top-level array**. Each item:
```json
{
  "id": "1a8724a52d432501548a8d8681bb1554c2d09778f8b9ed0882fc3442549980b7",
  "configuration": {
    "name": "docker.io/library/nginx:alpine",
    "creationDate": "2026-06-22T20:53:00Z",
    "descriptor": { "digest": "sha256:1a87...", "mediaType": "...index.v1+json", "size": 10333 }
  },
  "variants": [
    {
      "platform": { "architecture": "arm64", "os": "linux", "variant": "v8" },
      "size": 25876989,
      "digest": "sha256:1ff5c7ff...",
      "config": {
        "architecture": "arm64", "os": "linux",
        "config": {
          "Cmd": ["nginx","-g","daemon off;"],
          "Entrypoint": ["/docker-entrypoint.sh"],
          "Env": ["PATH=...","NGINX_VERSION=1.31.2", ...],
          "ExposedPorts": null,
          "Labels": { "maintainer": "..." },
          "WorkingDir": "/", "StopSignal": "SIGQUIT"
        },
        "rootfs": { "diff_ids": ["sha256:...", ...] }   // layer count = diff_ids.count
      }
    }
  ]
}
```
IMPORTANT: `image inspect <name>` returns the **same shape** as `image list`. The list
response already carries the full per-image detail. So you do **not** need a second CLI
call to render the detail panel — render it from the already-parsed `ImageSummary` (retain
`raw` like `ContainerSummary` does). Adding a `listImages()` client method is sufficient.
(An `inspectImages(refs:)` method is optional/nice-to-have; do not over-build.)

Disk size: prefer `variants[0].size` (compressed bytes on disk). If multiple variants,
sum them. The `configuration.descriptor.size` is the manifest size (~10KB) — NOT disk size;
do not use it for the size column.

## Steps

### 1. Model — new file `Sources/ContainerCore/Models/ImageModels.swift`
Define `public struct ImageSummary: Identifiable, Equatable, Sendable` with:
- `id: String` (full digest from top-level `id`)
- `name: String` (configuration.name; show "<none>" fallback if empty)
- `sizeBytes: UInt64?` (sum of variant sizes)
- `digest: String?` (configuration.descriptor.digest)
- `os: String?`, `architecture: String?` (from variants[0].platform)
- `createdAt: Date?`
- `layerCount: Int?` (variants[0].config.rootfs.diff_ids.count)
- `entrypoint: [String]`, `command: [String]`, `env: [String]`, `exposedPorts: [String]`
  (from variants[0].config.config; ExposedPorts is an object keyed "80/tcp" → use its keys, may be null)
- `raw: JSONValue`
Add computed helpers: `shortDigest` (12 chars of the digest hex, after stripping `sha256:`),
`platformDisplay` ("linux/arm64" or "--"), `repositoryTag` for name.
Keep it `Equatable + Sendable` (mandatory per CLAUDE.md).

### 2. Mapper — new file `Sources/ContainerCore/Models/ImageJSONMapper.swift`
`public enum ImageJSONMapper` with `public static func images(from data: Data) throws -> [ImageSummary]`.
- Reuse the lenient `JSONValue` accessors and the array/object/deepValues helpers already used
  by `ContainerJSONMapper`. Mirror its defensive multi-key style.
- Reuse the same ISO8601 date parsing approach (copy the two `ISO8601DateFormatter`s or factor a
  shared helper — but do NOT refactor `ContainerJSONMapper`'s privates; keep this self-contained
  to avoid churn).
- Parse defensively: missing `variants` → empty arrays / nil size; missing config → nil fields.

### 3. CLI client — `Sources/ContainerCore/Services/ContainerCLIClient.swift`
- Add `func listImages() async throws -> [ImageSummary]` to the `ContainerCLIClient` protocol.
- Implement in `ProcessContainerCLIClient`:
  `try await ImageJSONMapper.images(from: runJSON(arguments: ["image", "list", "--format", "json"]))`

### 4. Snapshot — `Sources/ContainerCore/Models/ContainerModels.swift`
- Add `images: [ImageSummary]` to `ContainerDashboardSnapshot` (default `[]`) — update the
  initializer (keep all existing params/defaults; add `images` param).
- Add `case images` to `DashboardSection` (with `title = "Images"`). Keep CaseIterable ordering
  sensible: containers, images, volumes, networks (images right after containers reads well).

### 5. Polling — `Sources/ContainerCore/Services/PollingCoordinator.swift`
- Add `cachedImages: [ResourceSummary]`-style cache: `private var cachedImages: [ImageSummary] = []`.
- Fetch images like networks/volumes are fetched (foreground/force/empty), via
  `(try? await client.listImages()) ?? cachedImages`. Images change rarely, so background
  refresh only when empty is fine — match the networks/volumes pattern exactly.
- Pass `images: cachedImages` into BOTH the success and the catch-path `ContainerDashboardSnapshot`
  initializers, and into `staleSnapshot`.

### 6. ViewModel — `Sources/ContainerCore/ViewModels/DashboardViewModel.swift`
- Add `@Published public var selectedImageID: String?`.
- Add `public var selectedImage: ImageSummary?` computed (mirror `selectedContainer`).
- In `refresh`, keep selectedImageID valid if the image set changes (mirror the container logic,
  but don't auto-select the first image unless you also do it for containers — keep behavior
  minimal: clear selection if the selected image vanished).

### 7. Views — new file `Sources/ContainerMenuBar/ImageViews.swift`
- `ImageRowView` (name, platform chip, size, shortDigest, relative age) — mirror `ContainerRowView` styling.
- `ImageDetailView` (full digest with CopyButton, size, platform, created, layer count,
  Entrypoint, Cmd, Exposed ports, Env list) — mirror `ContainerDetailView` sections/`SectionHeader`.
  NOTE: `SectionHeader`, `StatCell`, `CopyButton` are `private` in ContainerViews.swift. Define your
  own small private equivalents in ImageViews.swift (do NOT change their access level in
  ContainerViews.swift — that creates needless cross-file coupling/merge risk).

### 8. Wire into DashboardView — `Sources/ContainerMenuBar/DashboardView.swift`
- The `sectionPicker` already iterates `DashboardSection.allCases`, so the new segment appears
  automatically once the enum case exists.
- Add a `case .images:` branch in `content` rendering an images master-detail (list 310pt wide +
  Divider + ImageDetailView), mirroring `containersContent`.
- Add `.images` to the `count(for:)` switch (return `snapshot.images.count`).
- Optionally add an "Images" `MetricBadge` to the summary strip.

### 9. Tests — `Sources/ContainerCoreSmokeTests/main.swift`
- Add `testParsesImageListShape()` using the real JSON above as a string literal fixture; assert
  name, sizeBytes (== variant size), shortDigest, os/arch, layerCount, entrypoint/cmd.
- Register it in `SmokeTests.main()` via `await suite.run(...)`.
- Add `listImages()` to the `MockContainerCLIClient` in this file (return one `ImageSummary`) so it
  still conforms to the protocol and the suite compiles.

## Definition of done
- `swift build` clean (no warnings introduced).
- `swift run ContainerCoreSmokeTests` → all PASS (existing 8 + new).
- No AppKit/SwiftUI imports added to ContainerCore. All new public types Equatable + Sendable.
- Commit on `feature/images-tab` with a clear message; do not push.
