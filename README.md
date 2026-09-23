# Jev Notch

A menu-bar macOS app that expands from the MacBook notch when Command is held, transcribes speech with Apple's Speech framework, asks TypeSafe Jev to choose typed workflow steps, and executes them through native macOS APIs. Local `gemma3:4b` is used only for inert text generation, rewriting, and summarization.

## Interaction

1. Launch **Jev Notch**. The first run asks for Microphone and Speech Recognition access.
2. Give Accessibility access when prompted by the menu-bar command. This is required for keyboard, window, and UI-control tools.
3. Hold either Command key for one second and speak. Double tap Command to cancel and collapse.
4. Release Command. Jev chooses a registered tool and supplies calibrated confidence.
5. Consequential or low-confidence actions show **Cancel** and **Run** before execution.

Responses are spoken with the local Piper ONNX voices already in this Mac's iCloud Drive. The app chooses `jarvis-medium.onnx` by default and discovers Bobby, Kristin, and HFC Female from matching `.onnx`/`.onnx.json` pairs. The menu bar has **Speak Responses** (on/off), **ONNX Voice**, **Choose ONNX Voice…**, **Test Voice**, and **Stop Speaking**. Starting a new Command hold interrupts narration. Piper is loaded from the installed executable (currently `/opt/anaconda3/bin/piper`); no speech service or generic macOS voice fallback is used. Confirmations are announced without reading private message bodies aloud.

Each completed result or confirmation shows a small elapsed-time and estimated Jev API-cost line underneath. Time starts when Command is released and excludes time spent waiting for you to confirm. Cost sums `usage.input_tokens` across all Jev routing calls for that request at TypeSafe's published $0.042 per million input tokens; local Ollama/device costs are not included. If Jev does not report usage for an attempted call, the cost reads “unavailable” rather than an invented zero.

For simple requests, Jev makes one typed tool decision and the app runs it immediately. For multi-step requests, Jev chooses one action at a time, observes the real result, and then chooses the next action or `workflow.finish`. Workflows stop after eight steps or if an action repeats without progress.

Normal keyboard shortcuts are left alone: pressing another key while Command is held cancels voice activation.

## API key

The app reads `TYPESAFE_API_KEY` or a Keychain generic password with service `com.jevnotch.typesafe` and account `api-key`. The menu-bar item **Set TypeSafe API Key…** stores it in Keychain without putting it in source or logs.

## Local text model

Install Ollama with `gemma3:4b`. The app connects only to `http://127.0.0.1:11434`, verifies that the exact model is installed, starts the local Homebrew Ollama daemon when necessary, and preloads the model for faster text generation. Gemma never receives the tool catalog and has no path to native executors.

## Spotify setup

The installed Spotify desktop app supports pause, resume, skip, and now playing immediately. To play a named song, create a Spotify developer app, register the exact redirect URI `http://127.0.0.1:43879/callback`, and use the menu bar commands **Set Spotify Client ID…** then **Connect Spotify…** once. The app uses Spotify's PKCE authorization flow and stores the refresh token in Keychain. No client secret is used. A named-song request searches Spotify's catalog, requires a clear title match, starts the returned track URI through the desktop app, and verifies the actual current track before reporting success. Example: “Play Blinding Lights by The Weeknd on Spotify.”

## Messages

“Text Alex saying I’m on my way” resolves an exact Contacts name, displays the recipient, address, and complete text for confirmation, then sends through Messages after **Run**. If a contact has several possible matching numbers, say the phone number explicitly. “Send an SMS to +15551234567 saying I’m late” uses the paired iPhone SMS service when available. “Draft a message to Alex saying…” prepares the message without sending. The app reports that Messages accepted the send request; actual delivery status remains in Messages.

## Build

```sh
npm install
npm test
npm run build
open "outputs/Jev Notch.app"
```

The final command compiles the native SwiftUI executable, assembles the `.app`, and applies an ad-hoc signature. The earlier web prototype remains available through `npm run build:web`, but it is not used by the app at runtime.

## Architecture

- `AppDelegate`: Command-hold state machine, confirmation policy, lifecycle.
- `SpeechController`: native microphone capture and partial/final transcription.
- `JevClient`: one TypeSafe request with a typed `choice` for routing and a `noul` confirmation gate.
- `WorkflowCoordinator`: bounded observe-decide-act loop with step history, confirmations, repetition detection, and an eight-step ceiling.
- `OllamaTextClient`: local text-only worker with no tool-calling interface.
- `ToolEngine`: finite, inspectable native tool registry and local argument resolution.
- `NotchPanelController`: transparent, always-on-top AppKit panel hosting the native SwiftUI surface.
- `NotchSurface`: compact notch geometry, animated border beam, voice glow, visible collapse/power controls, and state transitions.
- `ThinkingOrbs`: the official MIT-licensed SwiftUI port from Libraries.dev, vendored from the upstream repository.

Expand the notch to reveal its controls. The chevron collapses it and the red power button fully quits it. **Quit Jev Notch** remains available from the menu-bar icon as a second exit path.

Jev deliberately does not generate commands or free-form JSON. It selects one registered tool from a closed choice set. Concrete arguments are extracted from the transcript, native observations, finite candidates, or typed artifacts from previous steps. This matches System One's closed-choice architecture and prevents invented tool names.

## Included tool families

The registry contains more than sixty actions: context and UI inspection, running apps, app lifecycle, Dia/Safari/Chrome browser navigation and search, file search/read/open, keyboard editing, clipboard, focused-window controls and tiling, named Accessibility controls, scrolling, volume, Music and Spotify playback, Messages drafts and confirmed sends, Calendar, Reminders, Contacts, Notes, Mail search/drafts, Apple Shortcuts, local text transformations, and confirmation-gated shell commands.

Contextual text requests such as “Summarize this page,” “Explain the selected text,” and “What does this page say about refunds?” use Jev to select a text operation, read only the named source through browser Accessibility or the actual text selection, then ask local Gemma to produce the words. If the page or selection is unreadable, the app fails clearly instead of silently using stale clipboard contents. This is grounded page/selection assistance, not general web research or visual understanding.

Other mail providers, third-party messaging networks, browser extensions, computer vision, and document converters still need separate integrations. This build provides concrete adapters for Spotify and macOS Messages only.
