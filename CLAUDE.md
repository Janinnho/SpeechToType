# CLAUDE.md — SpeechToType

macOS menu-bar app for speech-to-text dictation with a global hotkey. Records audio (or
streams live), transcribes via a chosen provider, and inserts the text into the focused
app. Also offers AI text rewriting. SwiftUI + AppKit.

## Repo layout (nested!)

```
SpeechToType/                     ← repo root (README, appcast.xml, Documentation/, CLAUDE.md)
└── SpeechToType/                 ← Xcode project dir (SpeechToType.xcodeproj, MicrosoftSpeechSDK/)
    └── SpeechToType/             ← Swift sources (Models/, Services/, Views/, Localizable.xcstrings)
```

The Xcode project uses **file-system-synchronized groups** → new files under the sources
dir are picked up automatically (no need to edit the project to add a `.swift` file).

## Build & run

```bash
cd SpeechToType
xcodebuild -project SpeechToType.xcodeproj -scheme SpeechToType -destination 'platform=macOS' build
# run the built app:
open ~/Library/Developer/Xcode/DerivedData/SpeechToType-*/Build/Products/Debug/SpeechToType.app
```

- Deployment target: **macOS 26.2**. Not sandboxed; hardened runtime on.
- Entitlements (`SpeechToType/SpeechToType.entitlements`): `device.audio-input`,
  `cs.disable-library-validation` (needed because the Microsoft Speech framework is signed
  by a different team).
- Needs Accessibility permission (global hotkey + synthetic keystrokes) and Microphone +
  Speech Recognition permission (already declared in Info.plist).

## Architecture

**Orchestration:** `SpeechToTypeApp.swift` (`AppDelegate.setupRecordingHandlers`) wires
`HotkeyManager` callbacks → recording/transcription → insertion → history.

**Core services** (`SpeechToType/SpeechToType/Services/`):
- `AudioRecorder` — AVAudioRecorder, m4a 16 kHz mono; mic device enumeration.
- `HotkeyManager` — global CGEvent tap; 3 triggers: direct dictation (hold),
  continuous (double-tap toggle), rewrite (key combo). Calls `onRecordingStarted/Stopped`.
- `OpenAIService.transcribe(audioURL:model:)` — **batch** transcription router by
  `settings.speechModelProvider`: `.openAI`, `.local` (self-hosted Whisper), `.appleSpeech`,
  `.gemini`, `.azureFoundry` (Azure MAI-Transcribe via REST).
- `TextRewriteService` — text rewriting router: OpenAI, Anthropic, Ollama, Apple
  Intelligence, Gemini.
- `TextInputService` — inserts text into focused app. `insertText` uses clipboard+Cmd-V,
  or types directly (no clipboard) when `copyToClipboardOnInsert == false`. Also hosts
  `LiveTypingSession` (live-mode accumulator/preview).
- `AzureRealtimeService` / `AppleRealtimeService` — live streaming (see below).
- `TranscriptionHistoryManager` — persisted history records.

**Models:** `AppSettings` (singleton, all settings via UserDefaults `didSet`),
`TranscriptionRecord`. **Views:** Settings, Onboarding, Dictionary, History, Rewrite,
Status, RecordingOverlayWindow, TextRewritePopupWindow.

## Providers

- Speech (`SpeechModelProvider`): `openai`, `local`, `appleSpeech`, `gemini`, `azureFoundry`.
- Text (`TextProcessingProvider`): `openai`, `anthropic`, `ollama`, `appleIntelligence`, `gemini`.
- **OpenAI models** (`TranscriptionModel`): `gpt-transcribe` (batch, default for new installs),
  `gpt-live-transcribe` (**realtime only**, no `/v1/audio/transcriptions`), plus the legacy
  `gpt-4o-*-transcribe`. The two new ones send `languages[]` (from `openAISpeechLanguage`,
  "auto" ⇒ field omitted) + `keywords[]`; the legacy ones keep `language=de` + the combined
  dictionary prompt. Branch on `usesLanguagesAndKeywords` / `isRealtimeOnly` / `batchFallback`.
- **Azure Foundry MAI**: fast-transcription REST `…/speechtotext/transcriptions:transcribe`
  with `enhancedMode` (model `mai-transcribe-1.5`, lowercase!). Dictionary → `phraseList`.
  m4a is converted to WAV before upload (`convertToWav`) because MAI-Transcribe only
  accepts WAV/MP3/FLAC. Endpoint/key/model are user-entered (never hardcoded).

## Real-time / live mode

Optional per provider; enabled in Settings. Behavior: **while speaking** the running text
is shown only in the floating overlay; **on key release** the complete, formatted text is
inserted once (no backspaces → never overwrites existing text). History label
"GPT Live Transcribe (…)" / "Azure Realtime (…)" / "Apple Speech (Realtime)".

- All engines implement protocol `RealtimeTranscriber` (`start(onPartial:onFinal:onError:)`,
  `stop()`); the live path in `AppDelegate` is provider-agnostic (`realtimeTranscriber(for:)`).
- `OpenAIRealtimeService` — Realtime API over `URLSessionWebSocketTask`, `session.update` with
  `session.type = "transcription"`, mic audio as PCM16 mono 24 kHz base64 in
  `input_audio_buffer.append`. `turn_detection` **must** be `null` — the model rejects any turn
  detection config — so the model streams deltas on its own and the single turn is closed by
  `stop()`, which sends `input_audio_buffer.commit` and then **blocks** (bounded, 2.5 s) until
  `completed` lands, because `stopRealtime` reads `fullText()` right after. Incoming `…transcription.delta`
  events are incremental → accumulated per `item_id` before hitting `onPartial`. Switched on by
  selecting the `gpt-live-transcribe` model (no separate toggle). Settings:
  `openAISpeechLanguage` + `openAIRealtimeDelay`. One instance per dictation, not a singleton.
- `AzureRealtimeService` — Microsoft Speech SDK (`SPXSpeechRecognizer`, continuous
  recognition, `PhraseListGrammar`). Uses Azure standard streaming models (NOT MAI-Transcribe).
  Setting: `azureRealtimeEnabled` + `azureRealtimeLanguage`.
- `AppleRealtimeService` — on-device `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26) driven by
  `AVAudioEngine`; `SFSpeechRecognizer` is only used for the authorization prompt. Phrase-by-phrase
  volatile + finalized results, no network, no extra framework. Setting: `appleRealtimeEnabled`.
- `LiveTypingSession` accumulates finals + last partial → `fullText()` for insertion; it is
  thread-safe (events arrive on background threads). Contract: `onPartial` **replaces** the
  interim, `onFinal` **appends** — so engines with delta-style output must accumulate first.
- `AppDelegate`'s `onError` closure calls `stop()` **synchronously on the callback thread**, so a
  blocking `stop()` must pre-arm its drain on the error path (see `OpenAIRealtimeService.emitError`).
- All live engines use the system default microphone (the app's mic selector does not apply).

## Dictionary (custom vocabulary)

`AppSettings.dictionaryWords` + `dictionaryInstructions`. Helpers: `dictionaryPromptText`,
`dictionaryWordsText`, `dictionaryPhrases`, `openAIKeywords`, `dictionaryInstructionsText`.
Passed as: `keywords` + `prompt` (gpt-transcribe / gpt-live-transcribe — words and
instructions travel separately; `openAIKeywords` strips `<`, `>` and newlines as the API
requires), combined prompt (legacy gpt-4o-*, Gemini, Whisper), `phraseList` (Azure),
`PhraseListGrammar` (Azure realtime). Toggles: local Whisper, Azure, rewrite injection —
OpenAI has none, the dictionary is always applied.

## Microsoft Speech SDK dependency

Consumed via **SPM `binaryTarget`** in the local package `SpeechToType/MicrosoftSpeechSDK/`
(`Package.swift`), downloading the xcframework from Microsoft's storage on first resolve
(checksum-pinned). **Not committed to the repo.** SDK code is guarded with
`#if canImport(MicrosoftCognitiveServicesSpeech)` so the project still builds without it.
To bump the SDK: update URL + recompute checksum (`swift package compute-checksum <zip>`).
First build on a fresh clone needs internet to fetch it.

## Releases (Sparkle)

`appcast.xml` (repo root) is the update feed (`SUFeedURL` in Info.plist). Add a new
`<item>` at the top per release with `sparkle:version` (= build no.), `shortVersionString`,
`edSignature` (`sign_update <dmg>`), and `length` (bytes). Keep `CURRENT_PROJECT_VERSION`
(build) and `MARKETING_VERSION` in the project in sync with the appcast.

## Conventions

- All UI strings are localized via `Localizable.xcstrings` (de + en; source = en). Add keys
  there when adding UI text.
- Settings: add `@Published var` with `didSet` persistence in `AppSettings` + load in `init()`.
- New speech/text provider = add enum case + `displayName` + service router branch +
  Settings UI branch + `isConfigured`.
