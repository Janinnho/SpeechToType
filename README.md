# SpeechToType

A native macOS menu bar app for speech-to-text transcription using OpenAI's API. Simply hold a key to dictate, and your speech is instantly transcribed and inserted at your cursor position.

[![Download](https://img.shields.io/badge/Download-Latest%20Release-blue)](https://github.com/Janinnho/SpeechToType/releases/latest/download/SpeechToType.dmg)

## Features

- **Instant Dictation**: Hold the Control key (or a custom shortcut) to record, release to transcribe and insert text
- **Double-Tap for Continuous Recording**: Double-tap the hotkey to toggle continuous recording mode for longer dictations
- **Visual Recording Indicator**: A floating overlay with sound wave animation shows when recording is active
- **Text Rewriting**: Select any text and use a shortcut to rewrite it with AI assistance (grammar correction, elaboration, or custom prompts)
- **Multiple Transcription Models**: Choose between GPT-4o Mini (fast), GPT-4o (higher quality), or GPT-4o with speaker diarization
- **Customizable Shortcuts**: Configure your own keyboard shortcuts for recording and text rewriting
- **Transcription History**: Browse, search, and reuse your past transcriptions
- **Auto-Delete**: Optionally delete old transcriptions after a set period
- **Native macOS Experience**: Built with SwiftUI for a seamless Mac experience
- **Menu Bar Integration**: Quick access from your menu bar
- **Auto-Updates**: Automatic update checking via Sparkle

## Requirements

- macOS 14.0 or later
- OpenAI API key

## Installation

1. [Download the latest release](https://github.com/Janinnho/SpeechToType/releases/latest/download/SpeechToType.dmg)
2. Open the DMG and drag SpeechToType to your Applications folder
3. Launch SpeechToType
4. Grant the required permissions (Microphone and Accessibility)
5. Enter your OpenAI API key

## Usage

### Basic Dictation
- **Hold** the Control key (default) to start recording
- **Release** to stop recording and transcribe
- The transcribed text is automatically inserted at your cursor position

### Continuous Recording
- **Double-tap** the recording hotkey to enable continuous mode
- Recording continues until you tap the hotkey again
- Perfect for longer dictations

### Text Rewriting
- **Select** any text in any application
- Press **Cmd+R** (default) to open the rewrite popup
- Choose from:
  - **Grammar**: Fix spelling and grammar errors
  - **Elaborate**: Expand and improve the text
  - **Custom**: Enter your own prompt for custom transformations
- Click "Insert" to replace the selected text with the result

## Settings

Access settings from the menu bar icon or press **Cmd+,**:

- **API Configuration**: Enter your OpenAI API key
- **Transcription Model**: Choose your preferred transcription model
- **Text Rewriting**: Enable/disable and select GPT model (GPT-4o, GPT-5, GPT-5.2)
- **Shortcuts**: Customize recording and rewrite keyboard shortcuts
- **History**: Configure auto-delete period for transcriptions
- **Updates**: Manage automatic update settings

## Privacy

- Your audio recordings are processed directly via OpenAI's API
- Recordings are temporarily stored and deleted after transcription
- Your API key is stored locally on your Mac
- No data is collected or shared by the app itself

## License

MIT License

## Acknowledgments

- Built with SwiftUI
- Transcription powered by OpenAI
- Auto-updates via [Sparkle](https://sparkle-project.org/)
