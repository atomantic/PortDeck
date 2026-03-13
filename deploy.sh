#!/bin/bash
set -euo pipefail

# PortOS Recall - Local TestFlight Deploy
# Usage: ./deploy.sh [--skip-tests]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "❌ .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Key path (already expanded via $HOME in .env)
KEY_PATH="$APPSTORE_API_PRIVATE_KEY_PATH"

if [ ! -f "$KEY_PATH" ]; then
    echo "❌ API key not found at: $KEY_PATH"
    exit 1
fi

# Ensure altool can find the key (it only checks specific directories)
mkdir -p ~/.private_keys
KEY_FILENAME="AuthKey_${APPSTORE_API_KEY_ID}.p8"
if [ ! -f ~/.private_keys/"$KEY_FILENAME" ]; then
    ln -sf "$KEY_PATH" ~/.private_keys/"$KEY_FILENAME"
    echo "🔑 Symlinked API key to ~/.private_keys/"
fi

PROJECT="PortOS_Recall.xcodeproj"
SCHEME="PortOS_Recall"
BUILD_DIR="$SCRIPT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

# Auto-increment build number
CURRENT_BUILD=$(grep CURRENT_PROJECT_VERSION project.yml | head -1 | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

# Regenerate Xcode project
echo "⚙️  Regenerating Xcode project..."
xcodegen generate

# Run tests (unless skipped)
if [ "${1:-}" != "--skip-tests" ]; then
    echo "🧪 Running tests..."
    DESTINATION=$(
        if xcrun simctl list devices available | grep -q "iPhone 16"; then
            echo "platform=iOS Simulator,name=iPhone 16"
        elif xcrun simctl list devices available | grep -q "iPhone 15"; then
            echo "platform=iOS Simulator,name=iPhone 15"
        else
            echo "platform=iOS Simulator,name=iPhone 14"
        fi
    )
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -only-testing:PortOS_RecallTests \
        -destination "$DESTINATION" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
    echo "✅ Tests passed"
fi

# Clean build directory
rm -rf "$BUILD_DIR"

# Archive
echo "📦 Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    -quiet

echo "✅ Archive complete"

# Create exportOptions.plist
cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

# Export IPA
echo "📤 Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$APPSTORE_API_KEY_ID" \
    -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
    -quiet

echo "✅ IPA exported"

# Upload to TestFlight
IPA_PATH="$EXPORT_PATH/$SCHEME.ipa"
if [ ! -f "$IPA_PATH" ]; then
    echo "❌ IPA not found at $IPA_PATH"
    ls -la "$EXPORT_PATH/"
    exit 1
fi

echo "🚀 Uploading to TestFlight..."
xcrun altool --upload-app \
    --file "$IPA_PATH" \
    --type ios \
    --apiKey "$APPSTORE_API_KEY_ID" \
    --apiIssuer "$APPSTORE_ISSUER_ID"

UPLOAD_EXIT=$?
if [ $UPLOAD_EXIT -ne 0 ]; then
    echo "❌ Upload failed with exit code $UPLOAD_EXIT"
    exit $UPLOAD_EXIT
fi

echo "✅ Upload complete! Build $NEW_BUILD submitted to TestFlight."
echo "🔗 https://appstoreconnect.apple.com/teams/69a6de6e-c0f9-47e3-e053-5b8c7c11a4d1/apps/6760561316/testflight"

# Commit the build number bump
git add project.yml "$PROJECT/project.pbxproj"
git commit -m "build: bump to build $NEW_BUILD"
echo "📝 Committed build number bump"

# Clean up
rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
