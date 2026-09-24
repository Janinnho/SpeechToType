# CLAUDE.md — SpeechToType

macOS menu-bar app for speech-to-text dictation with a global hotkey. Records audio (or
streams live), transcribes via a chosen provider, and inserts the text into the focused
app. Also offers AI text rewriting, a chat with the text models (ChatGPT-style) and
text templates ("Vorlagen"). SwiftUI + AppKit.

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
`HotkeyManager` callbacks → recording/transcription → insertion → history. Recordings started
with the start page's record button (`HotkeyManager.recordingSource == .button`, captured at
stop) skip the insertion into the focused app: `AppDelegate.deliver` routes their text by
`AppSettings.buttonDictationTarget` — `.messageField` (default; via
`AppNavigation.pendingComposerDictation` into the start page composer), `.previousApp`
(re-activates `TextInputService.getPreviousApp()`, then inserts; falls back to the message
field) or `.clipboard`. History is recorded either way.

**Core services** (`SpeechToType/SpeechToType/Services/`):
- `AudioRecorder` — AVAudioRecorder, m4a 16 kHz mono; mic device enumeration.
- `HotkeyManager` — global CGEvent tap; 3 triggers: direct dictation (hold),
  continuous (double-tap toggle), rewrite (key combo). Calls `onRecordingStarted/Stopped`.
- `OpenAIService.transcribe(audioURL:model:)` — **batch** transcription router by
  `settings.speechModelProvider`: `.openAI`, `.local` (self-hosted Whisper), `.appleSpeech`,
  `.gemini` (Gemini 3.5 Transcribe via the Interactions API), `.azureFoundry` (Azure
  MAI-Transcribe via REST).
- `TextRewriteService` — text rewriting router: OpenAI, Anthropic, Ollama, Apple
  Intelligence, Gemini.
- `TextInputService` — inserts text into focused app. `insertText` uses clipboard+Cmd-V,
  or types directly (no clipboard) when `copyToClipboardOnInsert == false`. Also hosts
  `LiveTypingSession` (live-mode accumulator/preview).
- `AzureRealtimeService` / `AppleRealtimeService` / `GeminiRealtimeService` — live
  streaming (see below).
- `TranscriptionHistoryManager` — persisted history records.
- `ChatManager` / `ChatService` / `ChatAttachmentStore` — chat (see below).
- `TemplateStore` — "Vorlagen": plain text snippets with an optional title (`TextTemplate.title`;
  lists fall back to the text's first line via `displayTitle`; `Templates/templates.json`,
  debounced saves; files from before titles decode with an empty title).

**Models:** `AppSettings` (singleton, all settings via UserDefaults `didSet`),
`TranscriptionRecord`, `ChatModels` (conversation/message/attachment/`ChatModelSelection`).
**Views:** Home (dashboard), History, Dictionary, Chat*, Rewrite, Templates, Settings (panes
incl. Chat), Onboarding, Markdown, RecordingOverlayWindow, TextRewritePopupWindow, plus the shared
`DesignSystem.swift` (see "Design").

## Providers

- Speech (`SpeechModelProvider`): `openai`, `local`, `appleSpeech`, `gemini`, `azureFoundry`.
- Text (`TextProcessingProvider`): `openai`, `anthropic`, `ollama`, `appleIntelligence`, `gemini`.
- **OpenAI speech models** (`TranscriptionModel`): `gpt-transcribe` (batch, default) and
  `gpt-live-transcribe` (**realtime only**, no `/v1/audio/transcriptions`). Both send
  `languages[]` (from `openAISpeechLanguage`, "auto" ⇒ field omitted) + `keywords[]` + the
  dictionary instructions as `prompt`. Branch on `isRealtimeOnly` / `batchFallback`. The
  `gpt-4o-*-transcribe` models and `whisper-1` are deprecated (shutdown Feb 2027) and were
  removed; a stored legacy value falls back to `gpt-transcribe`.
- **Text models** (as of Sept 2026): `GPTModel` = `gpt-6-astra` / `gpt-6-sol` (default) /
  `gpt-6-luna`; `AnthropicModel` = `claude-fable-5-1` / `claude-opus-5-5` / `claude-sonnet-5`
  (default) / `claude-haiku-4-5`; `GeminiModel` = `gemini-3.8-flash` (default) /
  `gemini-3.1-pro-preview` (Pro exists on the Gemini API only as preview) / `gemini-3.5-flash-lite`.
  Stored ids of an earlier generation map to their successor via `init?(storedValue:)`
  (settings) and `ChatModelSelection.upgraded` (chats) — extend these maps when bumping models.
- The current text models reason before answering. Rewrites send `reasoning_effort: "low"`
  (OpenAI) / `output_config.effort: "low"` (Claude except Haiku 4.5, see `supportsEffort`) with
  an 8192-token limit, and take Claude's first `text` block (a thinking block can come first).
  Gemini requests carry no `temperature` (deprecated for the current models).
- **Gemini speech models** (`GeminiSpeechModel`): `gemini-3.5-transcribe` (unary, default)
  and `gemini-3.5-transcribe-live` (**Live API only**). Both are separate from `GeminiModel`,
  which stays reserved for text rewriting. The unary model runs on
  `POST /v1beta/interactions` (**not** `models/…:generateContent`) with
  `generation_config.transcription_config`: `language_codes` (BCP-47, `[]` ⇒ auto),
  `custom_vocabulary` (≤1000), `mode` (`{"type": "smart"|"verbatim"}`). Transcript comes back
  in `output_text`. The recorded m4a is converted to WAV first (`convertToWav`) because the
  API takes WAV/MP3/AIFF/AAC/OGG/FLAC only, and it travels inline base64 (20 MB request cap).
- **Azure Foundry MAI**: fast-transcription REST `…/speechtotext/transcriptions:transcribe`
  with `enhancedMode` (default model `mai-transcribe-2`, public preview; the id is not
  case-sensitive). MAI-Transcribe-2 is verbatim by default (keeps "äh"), so the app sends
  `modelOptions.transcribeStyle: "clean"` for it. Dictionary → `phraseList`.
  m4a is converted to WAV before upload (`convertToWav`) because MAI-Transcribe only
  accepts WAV/MP3/FLAC. Endpoint/key/model are user-entered (never hardcoded).

## Real-time / live mode

Optional per provider; enabled in Settings. Behavior: **while speaking** the running text
is shown only in the floating overlay; **on key release** the complete, formatted text is
inserted once (no backspaces → never overwrites existing text). History label
"GPT Live Transcribe (…)" / "Gemini 3.5 Transcribe Live (…)" / "Azure Realtime (…)" /
"Apple Speech (Realtime)". Batch runs are labelled by `AppSettings.speechModelDisplayName`
(provider-aware).

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
- `GeminiRealtimeService` — Gemini Live API over `URLSessionWebSocketTask`
  (`…GenerativeService.BidiGenerateContent?key=…`), mic audio as PCM16 mono **16 kHz** base64 in
  `realtimeInput.audio` (`mimeType: audio/pcm;rate=16000`). `setup.inputAudioTranscription`
  carries `languageCodes` / `customVocabulary` / `mode` (`SMART`/`VERBATIM`); audio is queued
  until `setupComplete`. Hybrid VAD: server VAD stays on (keeps the first word), `stop()` sends
  `realtimeInput.audioStreamEnd` and **blocks** (bounded, 2.5 s) for the trailing final.
  `serverContent.interimInputTranscription` ⇒ `onPartial` (replaces),
  `serverContent.inputTranscription` ⇒ `onFinal` (appends). Switched on by selecting the
  `gemini-3.5-transcribe-live` model. Sessions are capped at 10 minutes by the API.
  Settings: `geminiSpeechLanguage` + `geminiTranscriptionMode`. One instance per dictation.
- `AppleRealtimeService` — on-device `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26) driven by
  `AVAudioEngine`; `SFSpeechRecognizer` is only used for the authorization prompt. Phrase-by-phrase
  volatile + finalized results, no network, no extra framework. Setting: `appleRealtimeEnabled`.
- `LiveTypingSession` accumulates finals + last partial → `fullText()` for insertion; it is
  thread-safe (events arrive on background threads). Contract: `onPartial` **replaces** the
  interim, `onFinal` **appends** — so engines with delta-style output must accumulate first.
- `AppDelegate`'s `onError` closure calls `stop()` **synchronously on the callback thread**, so a
  blocking `stop()` must pre-arm its drain on the error path (see `OpenAIRealtimeService.emitError`).
- All live engines use the system default microphone (the app's mic selector does not apply).

## Design (Liquid Glass)

- `DesignSystem.swift` holds the shared look: `AppBackground` (slowly drifting `MeshGradient`,
  set as the window background via `.containerBackground(for: .window)` in `ContentView`; pauses
  while the window is inactive and with Reduce Motion), `glassCard()`, `insetField()` (for fields
  on glass — never glass on glass), `PageHeader`, `SectionTitle`, `EmptyStateView`, `IconBadge`,
  `KeyCap`, `InfoChip`, `PanelSearchField`, `StatTile`, `DictationOrb` and `FlowLayout`.
- Sidebar (`ContentView`) is one flat list of every `ContentTab` (no section headers).
  `AppNavigation.shared` holds the selected tab and the history selection so the dashboard can
  jump to a chat or history entry.
- Page patterns: two-pane pages (History, Chat, Templates) = a fixed-width floating glass list
  panel + content; single pages (Dictionary, Rewrite) = `ScrollView` with a max-width column of
  glass cards; Home = dashboard (status card, stats, recent items, composer in a bottom inset).
- The orb in Home's status card is a record button (`DictationRecordButton`): a click records
  until the next click (`startButtonRecording()` + `continueButtonRecording()`), holding it
  ≥ 0.35 s records until release — same live/batch path as the shortcut.
- Buttons use `.glass` / `.glassProminent`. Keep panel content within the panel's width — the
  detail column continues under the floating sidebar, so overflow slides under it. A segmented
  `Picker` sizes every segment for its longest title and overflows narrow panels (hence
  `HistoryFilterBar`).
- The recording overlay, menu bar popover, rewrite popup and onboarding use the same components;
  the settings forms stay native (`.formStyle(.grouped)`) with icon tiles in their sidebar.
- App icon: `SpeechToType/SpeechToTypeIcon.icon` (Icon Composer, referenced by
  `ASSETCATALOG_COMPILER_APPICON_NAME`) = violet→blue linear-gradient fill + one white glyph
  layer `Assets/Glyph.svg` (three waveform bars flowing into a text cursor) with translucency
  and a neutral shadow. Preview without Xcode: `xcrun actool … --app-icon SpeechToTypeIcon`, then
  `iconutil -c iconset` on the resulting `.icns`.

## Chat & Vorlagen

- Tabs: **Chat** (`ChatView`: conversation list + `ChatConversationView`) and **Vorlagen**
  (`TemplatesView`). The start page (`HomeView`) has a composer; sending there starts a
  conversation and switches to the chat tab.
- `ChatManager` (singleton) owns conversations, selection, per-conversation drafts and running
  replies — replies keep streaming when the view is gone. Live text goes through the separate
  `ChatStreamBuffer` (throttled to 20 Hz) so only `StreamingMessageView` re-renders per chunk.
- `ChatService.streamReply` works for every `TextProcessingProvider`: OpenAI chat completions
  (SSE), Anthropic Messages (SSE, `max_tokens` 16384, only `text_delta` is shown), Gemini
  `:streamGenerateContent?alt=sse` (skips `thought` parts), Ollama `/api/chat` (NDJSON), Apple
  Intelligence (`LanguageModelSession` rebuilt from a `Transcript`, history trimmed to ~9k chars,
  text only). It runs in a detached task from a `ChatProviderConfig` snapshot and yields the
  **accumulated** reply text, not deltas.
- Each conversation stores its model (`ChatModelSelection` = provider + model id); the picker
  lists every provider that is set up (`ChatModelCatalog.isConfigured`). `AppSettings.chatModel`
  = model for new chats (the last one picked; until then it follows the rewrite model and is
  not persisted). The Text-model settings pane shows all provider keys at once for this.
- Settings: `chatCustomInstructions` (system prompt of every chat), `chatAutoGenerateTitles`
  (the chat's own model writes a title after the first reply; fallback = first line).
- Attachments (`ChatAttachmentStore`): images → JPEG ≤2048 px (alpha flattened onto white);
  PDFs ≤10 MB (native for OpenAI/Anthropic/Gemini, extracted text for Ollama/Apple); text files
  ≤2 MB, inlined as `<file name="…">`. Paste and file drops are handled in `ComposerTextView`.
- Composer input is `ChatInputTextView` (NSTextView): Return sends, Shift/Option-Return = new
  line; the mic button dictates via `OpenAIService.transcribe`.
- Storage in `~/Library/Application Support/<bundle id>/`: `Chats/<uuid>.json` (one file per
  conversation), `ChatAttachments/` (unreferenced files are deleted on launch),
  `Templates/templates.json`.
- The default actor isolation is MainActor: types used off the main actor (chat models,
  `ChatService`, `ChatAttachmentStore`, the text provider/model enums) are `nonisolated`.

## Dictionary (custom vocabulary)

`AppSettings.dictionaryWords` + `dictionaryInstructions`. Helpers: `dictionaryPromptText`,
`dictionaryWordsText`, `dictionaryPhrases`, `openAIKeywords`, `dictionaryInstructionsText`.
Passed as: `keywords` + `prompt` (gpt-transcribe / gpt-live-transcribe — words and
instructions travel separately; `openAIKeywords` strips `<`, `>` and newlines as the API
requires), combined prompt (local Whisper, rewrite injection), `phraseList` (Azure),
`PhraseListGrammar` (Azure realtime), `custom_vocabulary` / `customVocabulary` (Gemini 3.5
Transcribe — words only; the model takes no prompt, so the instructions are not sent).
Toggles: local Whisper, Azure, rewrite injection — OpenAI and Gemini have none, the
dictionary is always applied.

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
