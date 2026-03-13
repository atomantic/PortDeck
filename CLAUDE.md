# PortOS Recall

Privacy-first iOS session recorder with on-device transcription and memory extraction.

## Tech Stack

- **SwiftUI** + **SwiftData** (iOS 17.0+)
- **XcodeGen** for project generation (`project.yml` is the source of truth, not the `.xcodeproj`)
- **AVAudioEngine** for recording, **SFSpeechRecognizer** for transcription, **NaturalLanguage** for analysis
- Bundle ID: `net.shadowpuppet.PortOSRecall`, Team: `TYQ32QCF6K`

## Build Commands

```bash
# Generate Xcode project (required after changing project.yml)
xcodegen generate

# Build
xcodebuild build -project PortOS_Recall.xcodeproj -scheme PortOS_Recall \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test -project PortOS_Recall.xcodeproj -scheme PortOS_Recall \
  -only-testing:PortOS_RecallTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## Git Workflow

After every feature or bug fix:

1. **Build and test** — verify `xcodebuild build` and `xcodebuild test` pass
2. **`/simplify`** — run code review for reuse, quality, and efficiency; fix issues found
3. **`/do:review`** — deep code review against best practices
4. **`/do:push`** — commit and push to GitHub
5. **`/release`** — when ready for TestFlight, run the local deploy (see below)

## TestFlight Deployment

Local deploy via `./deploy.sh` (used when CI build credits are exhausted):

```bash
./deploy.sh              # full: tests + archive + upload
./deploy.sh --skip-tests # skip tests for faster iteration
```

Requires `.env` file with App Store Connect API credentials (see `.env.example`).

CI/CD via GitHub Actions (`.github/workflows/ci.yml`) deploys automatically on push to `main`, `testflight`, or `release/*` branches.

## Key Patterns

- **Router**: 2-tab navigation (Sessions, Memories) with `NavigationPath` per tab
- **Models**: SwiftData `@Model` classes with enum-backed raw string properties
- **Brand colors**: Use `Color.recallPrimary`, `.recallRecording`, `.recallSuccess`, `.recallWarning` — not raw color literals
- **Duration formatting**: Use `TimeInterval.formattedDuration` extension — no inline formatters
- **Session display title**: Use `Session.displayTitle` — not inline `isEmpty` checks
- **Toasts**: Use `.toast()` modifier — never `window.alert`
- **Destructive actions**: Use `.destructiveConfirmation()` modifier — never `window.confirm`
- **Logging**: Use `RecallLogger.recording/transcription/analysis/info/success/warning/error`
