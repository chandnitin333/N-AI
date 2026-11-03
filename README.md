# N-AI

N-AI is a floating voice assistant for macOS and Windows. It listens to
microphone audio, transcribes speech, and displays the transcript and response
in a readable overlay. The app does not capture screen contents.

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
The key is never included in the app or installer. Grant microphone access
when the operating system asks.

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
