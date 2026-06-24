// SPDX-License-Identifier: Apache-2.0

import AppKit

// Explicit entry point. A bare `@main` on an NSApplicationDelegate built via SwiftPM
// (no Info.plist principal class / nib) does not reliably install the delegate, so
// `applicationDidFinishLaunching` never fires and no UI is created. Wiring the
// application and delegate up by hand guarantees the standard launch sequence runs.
// The process entry point is already on the main thread, which is the main actor.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    // NSApplication.delegate is weak; app.run() never returns, so this local keeps it alive.
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
