# Contributing to TrueSync Connector

Thanks for helping keep shop printers in sync. This repository is the **desktop connector only** (Windows + macOS). The TrueSync web app and cloud API stay in a separate private project.

## Maintainers

| Role | People |
|---|---|
| **Committers / reviewers** | SandHut, Nandakishore Gowda G |
| **Approvers** (SignPath signing requests) | SandHut, Nandakishore Gowda G |

Copyright holders: SandHut and Nandakishore Gowda G (see [LICENSE](LICENSE)).

## Development setup

### Windows client
- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- Optional: [NSIS](https://nsis.sourceforge.io/) for the installer (`makensis`)
- Optional: Python 3 (used by the installer packaging script)

```bash
./scripts/build-windows.sh
```

Cross-compiling from macOS works with `EnableWindowsTargeting`, but UI and printing must be validated on a real Windows PC with a printer driver.

### macOS client
- macOS 13+ with Xcode Command Line Tools
- Python 3 (icon packaging)

```bash
./scripts/build-macos.sh
./dist/macos/TrueSync\ Connector.app/Contents/MacOS/TrueSyncConnector --self-test
```

## API endpoint

By default the apps talk to the public TrueSync API. For local or self-hosted backends:

- Environment: `TRUESYNC_API_BASE=https://your-host.example/api`
- Or write `config.json` next to the app data folder (see README)

Never commit pairing secrets, certificates, or cloud credentials.

## Pull requests

1. Keep Windows and Mac behavior aligned when you change the poll / pair / print contract.
2. Prefer small, focused PRs with a short “why” in the description.
3. Do not add telemetry that sends document contents.
4. Update both platform READMEs if install or signing steps change.

## License

Contributions are accepted under the MIT License (see `LICENSE`). Copyright © 2026 SandHut and Nandakishore Gowda G.
