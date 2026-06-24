# Security Policy

## Supported versions

This project is pre-1.x in spirit and ships from `main`. Security fixes are
applied to the latest released version and `main`.

| Version | Supported |
| ------- | --------- |
| latest release / `main` | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Report privately via GitHub's
[private vulnerability reporting](https://github.com/hurryingauto3/container-mb/security/advisories/new)
(Security → Advisories → Report a vulnerability), or email **ah7072@nyu.edu**
with the details and reproduction steps.

We aim to acknowledge reports within 5 business days and to provide a fix or
mitigation timeline after triage. Please give us a reasonable window to address
the issue before any public disclosure.

## Security model

ContainerMenuBar is intentionally **read-only**: it runs a fixed set of
non-mutating `container` subcommands (`list`, `stats`, `inspect`,
`network list`, `volume list`, `system status`, `--version`). It does not:

- run a privileged or background helper service,
- accept network input, or
- write to the `container` runtime.

Arguments are passed to the subprocess as an argument vector (no shell
interpretation), and CLI JSON is treated as untrusted and parsed defensively
with a bounded-depth traversal.

### Binary resolution

The app executes the `container` binary it finds, probing trusted absolute
locations first (`/usr/local/bin`, `/opt/homebrew/bin`, `/usr/bin`) and falling
back to `PATH`. On a shared or misconfigured machine, an attacker who can place
a binary named `container` earlier in your `PATH`, or who can write to those
directories, could have their binary executed by this app (the same exposure as
running `container` yourself). Keep those directories and your `PATH` trusted.

## Installing safely

Release builds are currently **ad-hoc signed and not notarized**. macOS
Gatekeeper will warn the first time you open a downloaded copy. To install:

1. Prefer building from source (`make install`) if you want full provenance.
2. If using a release asset, verify the signature after unzipping:

   ```sh
   codesign --verify --strict --verbose=2 ContainerMenuBar.app
   spctl --assess --type execute --verbose ContainerMenuBar.app   # will note it is unnotarized
   ```

3. Only download release assets from the official
   [Releases page](https://github.com/hurryingauto3/container-mb/releases).

Notarized, Developer ID-signed builds are planned; the packaging script already
supports a real identity via `SIGN_IDENTITY` for maintainers who can notarize.
