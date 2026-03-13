# PortOS Recall

<p align="center">
  <img src="PortOSRecall.png" width="200" alt="PortOS Recall App Icon" />
</p>

A privacy-first iOS app for user-initiated conversation recording, on-device transcription, summarization, and structured memory extraction.

PortOS Recall is **not** an always-listening system -- it's a session recorder you manually start for meetings, D&D sessions, and conversations.

## Features

- **Session Recording** -- Start/stop audio capture with 5-minute auto-chunking for long sessions
- **On-Device Transcription** -- Speech-to-text via `SFSpeechRecognizer` with `requiresOnDeviceRecognition` (no data leaves your device)
- **NLP Analysis** -- Extracts summaries, bullet points, action items, decisions, and named entities using `NaturalLanguage` framework
- **Structured Memories** -- Automatically creates typed memory objects (facts, decisions, action items, people, topics) from each session
- **Audio Encryption** -- AES-GCM encryption via CryptoKit with per-device Keychain-stored keys
- **Background Processing** -- Transcription and analysis continue via `BGProcessingTask` if the app is backgrounded
- **Deep Linking** -- `portosrecall://` URL scheme for sessions, memories, and recording

## Architecture

- **SwiftUI** + **SwiftData** (iOS 17.0+)
- **AVAudioEngine** for 16kHz mono AAC recording
- **NaturalLanguage** framework (NLTagger, NLTokenizer) for entity/topic extraction
- **Apple Foundation Models** stub for iOS 26+ (A17 Pro+) with NLP fallback
- **XcodeGen** for project generation (`project.yml`)

## Project Structure

```
PortOS_Recall/
  Models/          Session, Participant, Memory, Enums
  Navigation/      Router, Routes, DeepLinkHandler
  Services/        AudioRecorder, AudioEncryption, TranscriptionService,
                   AnalysisService, MemoryExtractor, ProcessingPipeline,
                   BackgroundTaskManager, RecallLogger
  Views/
    Sessions/      SessionListView, SessionDetailView, RecordingView
    Memories/      MemoryListView, MemoryRowView
    Components/    ToastView, EmptyStateView, RecordingIndicator, AudioLevelView
  Extensions/      Color+Brand, Date+Formatting, TimeInterval+Formatting, View+Toast
```

## Development

```bash
# Generate Xcode project
brew install xcodegen
xcodegen generate

# Build
xcodebuild build \
  -project PortOS_Recall.xcodeproj \
  -scheme PortOS_Recall \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test \
  -project PortOS_Recall.xcodeproj \
  -scheme PortOS_Recall \
  -only-testing:PortOS_RecallTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## CI/CD

GitHub Actions pipeline deploys to TestFlight on push to `main`, `testflight`, or `release/*` branches. See `.github/workflows/ci.yml`.

## Privacy

All processing happens on-device. No audio, transcripts, or memories leave the device. Audio files are encrypted at rest with AES-GCM using a per-device key stored in the Secure Enclave Keychain.
