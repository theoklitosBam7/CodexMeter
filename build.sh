#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

ROOT="${0:A:h}"
BUILD="$ROOT/build"
APP="$BUILD/Codex Meter.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *)
    print -u2 "ERROR: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

TARGET="$ARCH-apple-macos13.0"
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

printf 'Swift compiler: %s\n' "$SWIFTC"
printf 'macOS SDK:      %s\n' "$SDK"
printf 'Target:         %s\n' "$TARGET"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

SOURCES=("$ROOT"/Sources/CodexMeter/*.swift)
if (( ${#SOURCES} == 0 )); then
  print -u2 "ERROR: No Swift sources found."
  exit 1
fi

"$SWIFTC" \
  -parse-as-library \
  -Osize \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework AppKit \
  "${SOURCES[@]}" \
  -o "$MACOS/CodexMeter"

codesign --force --sign - "$APP" >/dev/null
printf 'Built: %s\n' "$APP"
printf 'Run:   open "%s"\n' "$APP"
