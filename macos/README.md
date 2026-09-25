# TrueSync Connector for Mac

Requires **macOS 13 Ventura** or newer. One universal binary supports Apple silicon and Intel.

## Install

1. Open `TrueSync-Connector-Mac.dmg`.
2. Drag **TrueSync Connector** into Applications.
3. Open it → **Connect this Mac** → enter the code in TrueSync → Printers.
4. Choose this Mac and its printer in the workspace.

No QZ, Java, or .NET.

## Signing

- **Default local/CI build:** ad-hoc `codesign` only. Gatekeeper may block first launch (`Right-click → Open`).
- **Production:** set `MAC_SIGN_IDENTITY` (Developer ID Application) and notarize via `NOTARY_PROFILE` or Apple ID credentials. See [CODE_SIGNING.md](../CODE_SIGNING.md).

Apple Developer Program membership (~$99/year) is required for Developer ID + notarization. There is no free OSS substitute.

## Build

From the connector repository root:

```bash
./scripts/build-macos.sh
./dist/macos/TrueSync\ Connector.app/Contents/MacOS/TrueSyncConnector --self-test
```

See the main [README](../README.md) for API overrides (`TRUESYNC_API_BASE` / `config.json`).
