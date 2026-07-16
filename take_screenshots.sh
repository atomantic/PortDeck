#!/bin/bash
#
# Capture deterministic App Store screenshots for iPhone and iPad.
# Adapted from the MortalLoom screenshot workflow.
#
# Usage:
#   ./take_screenshots.sh
#   ./take_screenshots.sh --iphone-only
#   ./take_screenshots.sh --ipad-only
#   ./take_screenshots.sh --screen 01_fleet

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/PortDeck.xcodeproj"
SCHEME="PortDeck"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
CONFIG_FILE_PROJECT="$PROJECT_DIR/.screenshot_config.json"
CONFIG_FILE_TMP="/tmp/portdeck_screenshot_config.json"
DERIVED_DATA="$PROJECT_DIR/.build/ScreenshotDerivedData"

CAPTURE_IPHONE=true
CAPTURE_IPAD=true
TARGET_SCREEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iphone-only) CAPTURE_IPHONE=true; CAPTURE_IPAD=false; shift ;;
        --ipad-only) CAPTURE_IPHONE=false; CAPTURE_IPAD=true; shift ;;
        --screen)
            [[ $# -ge 2 ]] || { echo "❌ --screen requires a screenshot name"; exit 1; }
            TARGET_SCREEN="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--iphone-only|--ipad-only] [--screen <name>]"
            echo "Screens: 01_fleet 02_federation 03_capture 04_actions 05_action_form 06_privacy"
            exit 0
            ;;
        *) echo "❌ Unknown option: $1"; exit 1 ;;
    esac
done

discover_device() {
    local kind="$1"
    xcrun simctl list devices available -j | python3 -c '
import json, sys

kind = sys.argv[1]
data = json.load(sys.stdin)
if kind == "iphone":
    preferred = ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 15 Pro Max"]
    folder = "iphone_6.9"
    method = "testCaptureIPhoneScreenshots"
else:
    preferred = ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Pro (12.9-inch) (6th generation)"]
    folder = "ipad_13"
    method = "testCaptureIPadScreenshots"

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    os_version = runtime.replace("com.apple.CoreSimulator.SimRuntime.iOS-", "").replace("-", ".")
    for device in devices:
        if device.get("isAvailable"):
            candidates.append((device.get("name", ""), device.get("udid", ""), os_version))

for preferred_name in preferred:
    for name, udid, os_version in candidates:
        if name == preferred_name:
            print("|".join([udid, name, os_version, folder, method]))
            raise SystemExit(0)
raise SystemExit(1)
' "$kind"
}

DEVICES=()
if $CAPTURE_IPHONE; then
    IPHONE_SPEC="$(discover_device iphone)" || {
        echo "❌ No App Store-sized iPhone Pro Max simulator is installed."
        exit 1
    }
    DEVICES+=("$IPHONE_SPEC")
fi
if $CAPTURE_IPAD; then
    IPAD_SPEC="$(discover_device ipad)" || {
        echo "❌ No 13-inch iPad Pro simulator is installed."
        exit 1
    }
    DEVICES+=("$IPAD_SPEC")
fi

cleanup() {
    rm -f "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP"
    for device_spec in "${DEVICES[@]}"; do
        IFS='|' read -r udid _ <<< "$device_spec"
        xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

write_config() {
    local device_folder="$1"
    local config
    config=$(printf '{\n  "device": "%s",\n  "output_dir": "%s",\n  "target_screen": "%s"\n}\n' \
        "$device_folder" "$SCREENSHOTS_DIR" "$TARGET_SCREEN")
    printf '%s' "$config" > "$CONFIG_FILE_PROJECT"
    cp "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP"
}

echo "📸 PortOS App Store screenshot capture"
echo "   Output: $SCREENSHOTS_DIR/en/{device}/"
[[ -n "$TARGET_SCREEN" ]] && echo "   Screen: $TARGET_SCREEN"

echo "⚙️  Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate --quiet

for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r udid name os_version device_folder test_method <<< "$device_spec"
    echo "🔨 Building for $name · iOS $os_version..."
    xcodebuild build-for-testing \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet

    echo "🚀 Preparing $name..."
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance light >/dev/null 2>&1 || true
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --batteryState charged \
        --batteryLevel 100 \
        --wifiBars 3 \
        --cellularBars 4 >/dev/null 2>&1 || true

    write_config "$device_folder"
    echo "📷 Capturing $device_folder..."
    xcodebuild test-without-building \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$DERIVED_DATA" \
        -only-testing:"PortDeckUITests/ScreenshotTests/$test_method" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet

    count=$(find "$SCREENSHOTS_DIR/en/$device_folder" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
    echo "✅ $device_folder: $count screenshots"
done

echo "🎉 Screenshots are ready in $SCREENSHOTS_DIR/en/"
