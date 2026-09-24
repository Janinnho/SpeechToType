<div align="center">

# SpeechToType

**A powerful native macOS app that turns your voice into text — instantly.**

Hold a key, speak, and your words appear right where your cursor is. Fast, private, and fully customizable — with live transcription, AI rewriting and a built-in chat.

<br>

<img src="Github-Assets/Screenshot SpeechtoType-App.png" alt="SpeechToType home screen" width="760">

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

The app window adds a dashboard with your stats and recent activity, your transcription history, a custom dictionary, AI rewriting, a chat with your text models and reusable text templates.

## Features

### Speech-to-Text
- **Hold-to-Record**: Hold a key to record, release to transcribe and insert text instantly
- **Double-Tap Continuous Mode**: Double-tap for hands-free continuous recording — double-tap again to stop
- **Live Transcription**: With a live model, your words appear in the floating overlay while you speak; the finished text is inserted once when you're done
- **Record Button**: Click the record button on the home screen to start and stop, or hold it while you speak. Choose where the text goes: the home screen's message field, the last active app, or the clipboard
- **Custom Dictionary**: Teach the models names, product terms and jargon, plus extra instructions like formatting rules
- **Transcription History**: Browse, search, copy or re-insert past transcriptions and rewrites, with optional auto-delete

### Multiple Speech Providers
- **OpenAI** — GPT Transcribe, or GPT Live Transcribe with a live preview while you speak
- **Google Gemini** — Gemini 3.5 Transcribe and Gemini 3.5 Transcribe Live
- **Azure Foundry MAI** — MAI-Transcribe-2, plus an optional real-time mode
- **Apple Speech** — Fully on-device transcription using macOS built-in speech recognition, with an optional real-time mode and no API key needed
- **Local Whisper Server** — Connect to your own self-hosted Whisper instance for full privacy

### AI Text Rewriting
Select any text and rewrite it with AI — fix grammar, elaborate, translate, speak your own instruction, or apply a custom prompt.

- **OpenAI** (GPT-6 Astra, GPT-6 Sol, GPT-6 Luna)
- **Anthropic** (Claude Fable 5.1, Claude Opus 5.5, Claude Sonnet 5, Claude Haiku 4.5)
- **Google Gemini** (Gemini 3.8 Flash, Gemini 3.1 Pro Preview, Gemini 3.5 Flash-Lite)
- **Apple Intelligence** — On-device text processing via the FoundationModels framework, no API key required
- **Ollama** — Use any local model running on your machine

### Chat
Chat with any of these text models, like in ChatGPT: start right from the home screen, pick the model per conversation, add your own custom instructions, attach images, PDFs and text files, and dictate your messages. Conversations get AI-generated titles and stay in the Chat tab.

### Templates
Keep reusable text snippets — each with an optional title — and copy them with one click.

### Customizable
- **Custom Keyboard Shortcuts** for dictation, continuous recording and text rewriting
- **Choose your providers** independently for speech and text processing
- **Guided Onboarding** walks you through permissions and provider setup

### Native macOS Experience
- Built with SwiftUI in the macOS 26 **Liquid Glass** design, with an animated gradient background
- Recording, rewriting and settings are always one click away in the menu bar
- Automatic updates via Sparkle

## Installation

1. **[Download the latest release](https://github.com/Janinnho/SpeechToType/releases/latest/download/SpeechToType.dmg)**
2. Open the DMG and drag SpeechToType to your Applications folder
3. Launch SpeechToType and follow the onboarding setup
4. Grant Microphone and Accessibility permissions
5. Choose your preferred speech and text processing providers

## Usage

| Action | How |
|---|---|
| **Dictate** | Hold your dictation shortcut (default: Right Option ⌥) |
| **Continuous recording** | Double-tap the shortcut (default: Right Option ⌥), double-tap again to stop |
| **Record in the app** | Click the record button on the home screen (click again to stop), or hold it while you speak |
| **Rewrite text** | Select text, then press your rewrite shortcut (default: ⌥ Option + Space) |
| **Chat** | Type into the message field on the home screen, or open the Chat tab |
| **Open settings** | Click the menu bar icon or press Cmd+, |

## Privacy

- **On-device options available**: Use Apple Speech and Apple Intelligence for fully offline operation, or your own Whisper server and Ollama
- Audio recordings are temporarily stored and deleted immediately after transcription
- API keys, history, chats and templates are stored locally on your Mac
- No data is collected by the app — audio and text only go to the providers you choose

## License

MIT License

## Acknowledgments

- Built with SwiftUI
- Transcription powered by OpenAI, Google Gemini, Microsoft Azure, Apple Speech Recognition and Whisper
- Text processing powered by OpenAI, Anthropic, Google Gemini, Apple Intelligence and Ollama
- Auto-updates via [Sparkle](https://sparkle-project.org/)
