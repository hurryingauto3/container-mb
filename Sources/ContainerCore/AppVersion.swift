// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The single source of truth for the application's version.
///
/// `Scripts/package-app.sh` reads `AppVersion.marketing` from this file to stamp the bundle's
/// `CFBundleShortVersionString`, and the UI surfaces `AppVersion.current` so a user can always
/// confirm which build they are running. Update `marketing` (and the `CHANGELOG.md` entry) when
/// cutting a release; keep it in sync with the git tag (`vX.Y.Z`).
public enum AppVersion {
    /// Marketing (semantic) version, e.g. `1.0.0`. Keep `Scripts/package-app.sh`'s parser in mind
    /// when changing the formatting of this declaration — it greps for the string literal.
    public static let marketing = "1.0.0"

    /// User-facing version string, prefixed with `v` (e.g. `v1.0.0`).
    public static var current: String { "v\(marketing)" }
}
