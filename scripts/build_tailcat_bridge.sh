#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/Native/TailcatBridge"
OUTPUT="$ROOT/Vendor/PortDeckTailcat.xcframework"
TOOLS="$ROOT/build/tailcat-tools"

if ! command -v go >/dev/null 2>&1; then
  echo "Go 1.27.3 or newer is required to build the pinned Tailcat bridge." >&2
  exit 1
fi

mkdir -p "$TOOLS" "$ROOT/Vendor"
export GOBIN="$TOOLS"
export PATH="$GOBIN:$PATH"
cd "$MODULE"

# Includes the SDK/toolchain and all bridge inputs, so stale native binaries
# cannot survive a source, dependency, or Xcode update.
FINGERPRINT="$(
  { go version; xcrun --sdk iphoneos --show-sdk-version; xcodebuild -version; cat go.mod go.sum bridge.go build-tags.txt "$ROOT/scripts/build_tailcat_bridge.sh"; } | shasum -a 256 | cut -d ' ' -f 1
)"
if [[ -d "$OUTPUT" && -f "$OUTPUT/.source-fingerprint" && "$(cat "$OUTPUT/.source-fingerprint")" == "$FINGERPRINT" ]]; then
  echo "Tailcat bridge is current."
  exit 0
fi

go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
gomobile bind -target=ios,iossimulator -iosversion=17.0 \
  -tags="$(cat build-tags.txt)" -trimpath -ldflags='-s -w' \
  -o "$OUTPUT" .
printf '%s\n' "$FINGERPRINT" > "$OUTPUT/.source-fingerprint"
echo "Built $OUTPUT"
