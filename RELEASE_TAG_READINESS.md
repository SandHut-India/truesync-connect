# GitHub Release tag readiness

SignPath (and SmartScreen users) expect a public **download page**. For this project that page is:

**https://github.com/SandHut-India/truesync-connect/releases**

## Current state

If that URL shows no releases yet, the repository is still eligible for SignPath once the README documents the Releases page and the code-signing policy (already on the homepage [README](README.md)). Publish the first assets as soon as SignPath is approved and CI secrets exist.

## First release checklist

1. Confirm SignPath project `truesync-connect` / policy `release-signing` is linked to this repo.
2. Set GitHub Actions secret `SIGNPATH_API_TOKEN` and variable `SIGNPATH_ORGANIZATION_ID`.
3. From a clean `main` matching the public export:

   ```bash
   git tag -a v0.1.2 -m "TrueSync Connector v0.1.2"
   git push origin v0.1.2
   ```

4. Wait for the [Release workflow](.github/workflows/release.yml) to finish.
5. Approve the SignPath signing request (approvers: SandHut, Nandakishore Gowda G).
6. Confirm the GitHub Release lists `TrueSync-Connector-Windows.exe` (and the macOS DMG when built).

## Attribution on downloads

Release notes and the README state:

Free code signing provided by SignPath.io, certificate by SignPath Foundation
