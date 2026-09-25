# TrueSync Connector

**Open-source desktop connector for [TrueSync](https://truesync-2026.web.app/)** — pairs a shop computer with TrueSync so customer documents print through the installed Windows or macOS printer drivers.

| | |
|---|---|
| **Homepage** | https://truesync-2026.web.app/ · [GitHub](https://github.com/SandHut-India/truesync-connect) |
| **Downloads** | [GitHub Releases](https://github.com/SandHut-India/truesync-connect/releases) |
| **Maintainers** | SandHut, Nandakishore Gowda G |
| **License** | [MIT](LICENSE) |

| Platform | Stack | Installer |
|---|---|---|
| **Windows 10/11 x64** | .NET 10 WinForms, Windows.Data.Pdf | `TrueSync-Connector-Windows.exe` (NSIS) |
| **macOS 13+** (Apple silicon + Intel) | Swift / SwiftUI, CUPS, PDFKit | `TrueSync-Connector-Mac.dmg` |

No QZ Tray, no local web server, no Java, no custom root CA.

## Releases / downloads

Installers are published on the **[GitHub Releases](https://github.com/SandHut-India/truesync-connect/releases)** page for this repository.

Free code signing provided by SignPath.io, certificate by SignPath Foundation

Until the first `v*` tag is pushed and a release is published, that page will be empty. After SignPath approval and CI secrets are set, tag a version (for example `v0.1.2`) to build, sign the Windows installer, and attach assets there. See [RELEASE_TAG_READINESS.md](RELEASE_TAG_READINESS.md).

## What it does

1. Shows a one-time pairing code (TrueSync → Printers).
2. Polls TrueSync for print jobs for this computer.
3. Renders / sends the PDF with the OS printer driver.
4. Reports printed / failed / unconfirmed back to the workspace.

Pairing secrets stay on the machine (DPAPI on Windows, Keychain on Mac). Document contents are not kept in the result journal.

## Build

Clone from **https://github.com/SandHut-India/truesync-connect** (or use the `connector/` folder inside the TrueSync monorepo).

### Windows

```bash
# .NET 10 SDK required; NSIS + Python 3 for the installer
./scripts/build-windows.sh
# → dist/TrueSync-Connector-Windows.exe
```

Optional Authenticode (local PFX):

```bash
export WINDOWS_CERT_PATH=/path/to/cert.pfx
export WINDOWS_CERT_PASSWORD='…'   # never commit
./scripts/build-windows.sh
```

### macOS

```bash
# Xcode Command Line Tools + Python 3
./scripts/build-macos.sh
# → dist/TrueSync-Connector-Mac.dmg
./dist/macos/TrueSync\ Connector.app/Contents/MacOS/TrueSyncConnector --self-test
```

Optional Developer ID + notarization:

```bash
export MAC_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE=truesync-notary
./scripts/build-macos.sh
```

From the TrueSync monorepo root you can still run:

```bash
bash scripts/build-connector-windows.sh
bash scripts/build-connector-macos.sh
```

## Point at your own API

Default API: `https://truesync-2026.web.app/api/`

Override with either:

```bash
export TRUESYNC_API_BASE=https://your-host.example/api
```

or a `config.json` in the app data folder:

- Windows: `%LOCALAPPDATA%\TrueSyncConnector\config.json`
- macOS: `~/Library/Application Support/TrueSyncConnector/config.json`

```json
{ "apiBase": "https://your-host.example/api" }
```

## Signing and SmartScreen / Gatekeeper

**Honest status:** release installers are **not yet** publisher-signed with production certificates on this machine. Unsigned or ad-hoc builds will still trigger OS warnings.

| | Status | Path to fix |
|---|---|---|
| **Windows** | No Authenticode until SignPath (or a commercial cert) is configured. SmartScreen may show **Unknown publisher**. | Free OSS: apply at [SignPath Foundation](https://signpath.org/apply.html), then set `SIGNPATH_API_TOKEN` + `SIGNPATH_ORGANIZATION_ID` for tagged releases. |
| **macOS** | Default build uses ad-hoc `codesign`. Gatekeeper shows **unidentified developer**. | Paid [Apple Developer Program](https://developer.apple.com/programs/) (~$99/yr) → Developer ID Application identity + notarization (`MAC_SIGN_IDENTITY`, `NOTARY_PROFILE`). No free OSS equivalent. |

Full env vars, CI secrets, and workflow details: **[CODE_SIGNING.md](CODE_SIGNING.md)**.

This project does not weaken OS security settings.

## Code signing policy

Free code signing provided by SignPath.io, certificate by SignPath Foundation

| | |
|---|---|
| **What is signed** | Windows release installers (`TrueSync-Connector-Windows.exe`) built by GitHub Actions from this public repository on version tags (`v*`), submitted under SignPath project `truesync-connect` / policy `release-signing`. macOS DMGs are signed with an Apple Developer ID by project maintainers when configured — not by SignPath. |
| **Committers / reviewers** | SandHut, Nandakishore Gowda G |
| **Approvers** | SandHut, Nandakishore Gowda G (approve each SignPath signing request in the SignPath dashboard before the release is published) |
| **Privacy** | This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it. The connector contacts the TrueSync API only when the user pairs this computer (and afterward for job polling and print-result reporting to the configured API base). Pairing secrets stay on the device. |

See also [SignPath Foundation conditions](https://signpath.org/terms.html).

## Repository layout

```
assets/                 Shared icons
TrueSync.Connector/     Windows .NET project
windows/installer.nsi   Windows installer
macos/                  Swift sources, Bridge.h, entitlements
scripts/                Platform build scripts (signing-aware)
.signpath/              SignPath artifact configuration
.github/workflows/      CI build + tagged release
CODE_SIGNING.md         Signing setup (SignPath + Apple)
RELEASE_TAG_READINESS.md  First GitHub Release checklist
```

Release binaries produced under `dist/` are gitignored. Official TrueSync cloud downloads remain private S3 objects served to signed-in shop owners; community builds publish via GitHub Releases from this repo.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 SandHut and Nandakishore Gowda G
