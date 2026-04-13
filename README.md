<div align="center">

# SpeechToType

**A powerful native macOS menu bar app that turns your voice into text — instantly.**

Hold a key, speak, and your words appear right where your cursor is. Fast, private, and fully customizable.

<br>

<img src="Github-Assets/Screenshot SpeechtoType-App.png" alt="SpeechToType Screenshot" width="700">

<br><br>

<a href="https://github.com/Janinnho/SpeechToType/releases/latest/download/SpeechToType.dmg">
  <img src="Github-Assets/Download_for_macOS-Button.png" alt="Download for macOS" width="280">
</a>

<br>

*Requires macOS 26.2 or later*

</div>

---

## What it does

SpeechToType lives in your menu bar and lets you dictate text into any application. Hold your shortcut key, speak, release — and the transcribed text is inserted at your cursor. No switching apps, no copy-pasting.

## Features

### Speech-to-Text
- **Hold-to-Record**: Hold a key to record, release to transcribe and insert text instantly
- **Double-Tap Continuous Mode**: Double-tap for hands-free continuous recording — tap again to stop
- **Visual Recording Indicator**: Floating overlay with sound wave animation shows when you're recording
- **Transcription History**: Browse, search, and reuse past transcriptions with optional auto-delete

### Multiple Speech Providers
- **OpenAI Whisper** — High-accuracy cloud transcription with multiple model options
- **Apple Speech** — Fully on-device transcription using macOS built-in speech recognition, no API key needed
- **Local Whisper Server** — Connect to your own self-hosted Whisper instance for full privacy

### AI Text Rewriting
Select any text and rewrite it with AI — fix grammar, elaborate, or apply custom prompts.

- **OpenAI** (GPT-5.4, GPT-5.4-mini, GPT-5.4-nano, GPT-4o, GPT-4o-mini)
- **Anthropic** (Claude Sonnet 4, Claude Opus 4, Claude Haiku)
- **Apple Intelligence** — On-device text processing via the FoundationModels framework, no API key required
- **Ollama** — Use any local model running on your machine

### Customizable
- **Custom Keyboard Shortcuts** for recording and text rewriting
- **Choose your providers** independently for speech and text processing
- **Guided Onboarding** walks you through permissions and provider setup

### Native macOS Experience
- Built with SwiftUI for a fast, lightweight menu bar app
- Automatic updates via Sparkle
- Runs entirely in the menu bar — no dock icon, no clutter

## Installation

1. **[Download the latest release](https://github.com/Janinnho/SpeechToType/releases/latest/download/SpeechToType.dmg)**
2. Open the DMG and drag SpeechToType to your Applications folder
3. Launch SpeechToType and follow the onboarding setup
4. Grant Microphone and Accessibility permissions
5. Choose your preferred speech and text processing providers

## Usage

| Action | How |
|---|---|
| **Dictate** | Hold your recording shortcut (default: Control key) |
| **Continuous recording** | Double-tap the recording shortcut |
| **Rewrite text** | Select text, then press your rewrite shortcut (default: Cmd+R) |
| **Open settings** | Click the menu bar icon or press Cmd+, |

## Privacy

- **On-device options available**: Use Apple Speech and Apple Intelligence for fully offline operation
- Audio recordings are temporarily stored and deleted immediately after transcription
- API keys are stored locally on your Mac
- No data is collected or shared by the app

## License

MIT License

## Acknowledgments

- Built with SwiftUI
- Transcription powered by OpenAI, Apple Speech Recognition
- Text processing powered by OpenAI, Anthropic, Apple Intelligence, Ollama
- Auto-updates via [Sparkle](https://sparkle-project.org/)
