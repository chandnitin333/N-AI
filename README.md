# N-AI

N-AI is a floating interview assistant for macOS and Windows. It listens to
computer speaker output (system-audio loopback), filters for interviewer
questions, and displays those questions with AI-generated answers. It does not
open the microphone or capture screen video. Audio is processed in memory and
sent to OpenAI for transcription; the app does not save audio or transcripts to
disk.

## Configure the API key

Click the **key** button in the overlay, enter your own OpenAI API key, and
select **Save key**. N-AI stores it locally in a user-only settings file:

- macOS: `~/Library/Application Support/N-AI/.env`
- Windows: `%APPDATA%\N-AI\.env`

The file should contain:

```text
OPENAI_API_KEY=your_api_key
```

You can also create the `.env` file manually with `OPENAI_API_KEY=your_api_key`.
The key is never included in the app or installer. On macOS, allow N-AI under
**System Settings > Privacy & Security > Screen & System Audio Recording** when
prompted. Windows captures the active default speaker's loopback audio.

The status banner reports when capture starts, when system-audio frames arrive,
when speech is detected, and when a segment is being checked for a question.
N-AI keeps a short audio pre-roll to preserve the start of words, waits longer
through natural pauses, and uses the higher-accuracy transcription model.
If it stays on **waiting for audio frames**, check macOS Screen & System Audio
Recording permission and restart N-AI. If it reports audio frames but never
detects speech, make sure interview playback is audible through the active
system output and raise the system volume. N-AI does not open the microphone;
filtering is performed on the captured speaker-audio transcript, so it cannot
identify speakers in a mixed audio source with certainty.

## Build a macOS installer

Build natively on macOS with Xcode Command Line Tools, Python 3, and `hdiutil`
installed. macOS apps cannot be built in a Linux Docker container.

```bash
bash scripts/build_macos.sh
```

The script packages the SwiftUI overlay and Python backend into
`dist/macos/N-AI-macOS.dmg`. The generated app is unsigned; for distribution
outside your own machine, sign and notarize it with an Apple Developer ID.

## Build and download Windows executables with GitHub Actions

The Windows build runs on a native GitHub Actions Windows runner. Push changes
to `main` that affect the app/build files, or start **Build Windows installer**
manually from the repository's Actions tab. When the run completes, download
the `N-AI-Windows-*` artifact from the run's **Artifacts** section. It contains
the standalone app, guided installer, and setup instructions.

The installer is unsigned; test the executables on Windows and sign them
before public distribution.

To build natively on Windows instead, use
`powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1`.

## Run from source

Install dependencies and run the backend from the project directory:

```text
python -m pip install -r requirements.txt
python backend/main.py
```

For the native macOS overlay, compile and run from the project directory:

```text
swiftc macos/OverlayApp.swift macos/CaptureManager.swift macos/PythonBridge.swift -o N-AI
./N-AI
```
# N-AI
