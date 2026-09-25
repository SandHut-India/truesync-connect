# Code signing for TrueSync Connector

This document wires **how** Windows and macOS builds get signed. It does **not**
create certificates. Until real identities are enrolled, installs will still show
**Unknown publisher** (Windows SmartScreen) or **unidentified developer**
(macOS Gatekeeper).

Public repo: [SandHut-India/truesync-connect](https://github.com/SandHut-India/truesync-connect) (MIT).

**Maintainers / copyright:** SandHut and Nandakishore Gowda G.

**Downloads:** [GitHub Releases](https://github.com/SandHut-India/truesync-connect/releases)

Free code signing provided by SignPath.io, certificate by SignPath Foundation

| Role | People |
|---|---|
| **Committers / reviewers** | SandHut, Nandakishore Gowda G |
| **Approvers** | SandHut, Nandakishore Gowda G |

---

## Current status

| Platform | Local / CI without secrets | With credentials |
|---|---|---|
| **Windows** | Unsigned NSIS installer + app | Authenticode via local PFX **or** SignPath OSS on `v*` tags |
| **macOS** | Ad-hoc `codesign --sign -` | Developer ID Application + hardened runtime + notarization + staple |

There is **no free OSS equivalent** for Apple Developer ID / notarization.

---

## Windows — SignPath Foundation (recommended for OSS)

SignPath Foundation offers free Authenticode signing for qualifying open-source
projects. The certificate is issued to **SignPath Foundation** (they are the
listed publisher), not to an individual maintainer.

### Human steps (required)

1. Publish this MIT repo with tagged releases and the **Code signing policy**
   section on the README homepage (already present).
2. Apply: **https://signpath.org/apply.html**
3. After approval, in SignPath create/link project:
   - **Project slug:** `truesync-connect`
   - **Signing policy slug:** `release-signing`
   - **Repository URL:** `https://github.com/SandHut-India/truesync-connect`
   - **Trusted build system:** GitHub.com
   - **Default artifact configuration:** paste
     [`.signpath/artifact-configurations/default.xml`](.signpath/artifact-configurations/default.xml)
4. Create a SignPath API token (submitter on `release-signing`).
5. In GitHub → Settings → Secrets and variables → Actions:
   - Secret `SIGNPATH_API_TOKEN`
   - Variable `SIGNPATH_ORGANIZATION_ID`
6. Push a tag `v*` (e.g. `v0.1.2`). The
   [release workflow](.github/workflows/release.yml) builds the installer,
   uploads an unsigned artifact, submits to SignPath when secrets/vars exist,
   and attaches the result to a GitHub Release.
7. **Approve** each signing request in the SignPath dashboard (Foundation
   requirement).

Until step 2–5 complete, CI still publishes an **unsigned** Windows installer
and prints a workflow warning.

### Local Authenticode (optional / commercial cert)

```bash
export WINDOWS_CERT_PATH=/path/to/cert.pfx
export WINDOWS_CERT_PASSWORD='…'   # do not commit
./scripts/build-windows.sh
```

Or a custom command (file path appended):

```bash
export WINDOWS_SIGN_COMMAND='signtool sign /f "$WINDOWS_CERT_PATH" /p "$WINDOWS_CERT_PASSWORD" /tr http://timestamp.digicert.com /td sha256 /fd sha256'
./scripts/build-windows.sh
```

Requires `signtool` (Windows SDK) or `osslsigncode`. The script signs
`dist/win-x64/TrueSync Connector.exe` before NSIS packaging, then signs
`dist/TrueSync-Connector-Windows.exe`.

**Never commit** `.pfx` / `.p12` / passwords. They are gitignored.

---

## macOS — Apple Developer ID + notarization

### Human steps (required)

1. Enroll in the **Apple Developer Program** (~US$99/year):
   https://developer.apple.com/programs/
2. In Certificates, Identifiers & Profiles, create a
   **Developer ID Application** certificate (for distribution outside the Mac
   App Store).
3. Install the certificate + private key in Keychain Access on the build Mac
   (or export a `.p12` for CI — store only in secrets).
4. Create an app-specific password (appleid.apple.com) **or** store a notarytool
   keychain profile:

   ```bash
   xcrun notarytool store-credentials "truesync-notary" \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

### Local signed build

```bash
export MAC_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE=truesync-notary   # preferred
# Or instead of NOTARY_PROFILE:
# export APPLE_ID=you@example.com
# export APPLE_TEAM_ID=TEAMID
# export APPLE_APP_SPECIFIC_PASSWORD='…'
./scripts/build-macos.sh
```

When `MAC_SIGN_IDENTITY` is set, the script:

1. Codesigns the `.app` with **hardened runtime**, entitlements
   [`macos/TrueSync.entitlements`](macos/TrueSync.entitlements), and a secure
   timestamp.
2. Builds the DMG.
3. Submits the DMG with `xcrun notarytool submit … --wait`.
4. Staples the ticket to the app and DMG.

When unset, it falls back to ad-hoc signing and prints a Gatekeeper warning.

### CI secrets (optional)

| Secret | Purpose |
|---|---|
| `MAC_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID `.p12` |
| `MAC_CERTIFICATE_PASSWORD` | P12 password |
| `MAC_SIGN_IDENTITY` | Exact codesign identity string |
| `MAC_KEYCHAIN_PASSWORD` | Temp keychain unlock (optional; default generated) |
| `NOTARY_PROFILE` | Keychain profile name (if pre-provisioned on the runner — usually not) |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_SPECIFIC_PASSWORD` | notarytool credentials when no profile |

Without these, the release workflow still builds an ad-hoc DMG and warns that
Gatekeeper will block.

---

## Monorepo wrappers

From the TrueSync monorepo root, the same scripts run via:

```bash
bash scripts/build-connector-windows.sh
bash scripts/build-connector-macos.sh
```

Pass the same env vars; wrappers `exec` into `connector/scripts/`.

---

## What signing does **not** fix by itself

- **SmartScreen reputation** still needs download volume / age even after
  Authenticode; SignPath Foundation certificates help but first installs can
  still prompt until reputation builds.
- **macOS Gatekeeper** requires both Developer ID **and** notarization
  (stapled). Ad-hoc or signed-but-unnotarized builds remain blocked for other
  users.
- This pipeline does not invent or embed certificates. Human enrollment
  (SignPath application + Apple $99 membership) is mandatory before
  “Unknown publisher” / “unidentified developer” go away.
