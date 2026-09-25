#!/usr/bin/env bash
# Build the Windows self-contained app + NSIS installer into dist/
# Optional Authenticode signing when cert env vars (or WINDOWS_SIGN_COMMAND) are set.
# See CODE_SIGNING.md for env vars and SignPath OSS setup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBLISH_DIR='dist/win-x64'
APP_EXE="$PUBLISH_DIR/TrueSync Connector.exe"
INSTALLER='dist/TrueSync-Connector-Windows.exe'

sign_file() {
  local target="$1"
  if [[ ! -f "$target" ]]; then
    echo "Cannot sign missing file: $target" >&2
    return 1
  fi
  if [[ -n "${WINDOWS_SIGN_COMMAND:-}" ]]; then
    # Command receives the file path as $1 / %1 — expand via eval carefully.
    # Example: WINDOWS_SIGN_COMMAND='signtool sign /f cert.pfx /p "$WINDOWS_CERT_PASSWORD" /tr http://timestamp.digicert.com /td sha256 /fd sha256'
    # shellcheck disable=SC2086
    eval "$WINDOWS_SIGN_COMMAND" "\"$target\""
    return
  fi
  if [[ -z "${WINDOWS_CERT_PATH:-}" || -z "${WINDOWS_CERT_PASSWORD:-}" ]]; then
    return 1
  fi
  if command -v signtool >/dev/null 2>&1; then
    signtool sign \
      /f "$WINDOWS_CERT_PATH" \
      /p "$WINDOWS_CERT_PASSWORD" \
      /tr http://timestamp.digicert.com \
      /td sha256 \
      /fd sha256 \
      "$target"
    return
  fi
  if command -v osslsigncode >/dev/null 2>&1; then
    local signed="${target}.signed"
    osslsigncode sign \
      -pkcs12 "$WINDOWS_CERT_PATH" \
      -pass "$WINDOWS_CERT_PASSWORD" \
      -t http://timestamp.digicert.com \
      -in "$target" \
      -out "$signed"
    mv "$signed" "$target"
    return
  fi
  echo "Neither signtool nor osslsigncode found; cannot Authenticode-sign." >&2
  return 1
}

can_sign() {
  [[ -n "${WINDOWS_SIGN_COMMAND:-}" ]] || \
    { [[ -n "${WINDOWS_CERT_PATH:-}" && -n "${WINDOWS_CERT_PASSWORD:-}" ]]; }
}

"${DOTNET_BIN:-dotnet}" publish TrueSync.Connector -c Release -r win-x64 --self-contained true -o "$PUBLISH_DIR"
python3 - <<'PY'
from pathlib import Path
root = Path('dist/win-x64')
files = sorted(p.relative_to(root) for p in root.rglob('*') if p.is_file())
dirs = sorted((p.relative_to(root) for p in root.rglob('*') if p.is_dir()), key=lambda p: len(p.parts), reverse=True)
def escape(p):
    return str(p).replace('\\', '/').replace('/', '\\').replace('$', '$$').replace('"', '$\\"')
lines = [f'Delete "$INSTDIR\\{escape(p)}"' for p in files]
lines += [f'RMDir "$INSTDIR\\{escape(p)}"' for p in dirs]
Path('dist/uninstall-files.nsh').write_text('\n'.join(lines) + '\n')
PY

# Sign the published app before packaging so the installed binary is signed too.
if can_sign; then
  echo "Signing published app: $APP_EXE"
  sign_file "$APP_EXE"
else
  echo "WARNING: No Authenticode credentials (WINDOWS_CERT_PATH + WINDOWS_CERT_PASSWORD, or WINDOWS_SIGN_COMMAND)." >&2
  echo "  SmartScreen may warn \"Unknown publisher\" on first install." >&2
  echo "  For OSS releases prefer SignPath Foundation (see CODE_SIGNING.md)." >&2
fi

if command -v brew >/dev/null 2>&1 && [ -z "${NSISDIR:-}" ]; then
  export NSISDIR="$(brew --prefix makensis)/share/nsis"
fi
if ! command -v makensis >/dev/null 2>&1; then
  echo "makensis not found — published folder is $PUBLISH_DIR (no installer)." >&2
  exit 0
fi
makensis -V2 windows/installer.nsi

if can_sign; then
  echo "Signing installer: $INSTALLER"
  sign_file "$INSTALLER"
  echo "Signed $APP_EXE and $INSTALLER"
else
  echo "WARNING: Installer left unsigned — SmartScreen / Unknown publisher warnings expected." >&2
fi

echo "Built $INSTALLER"
