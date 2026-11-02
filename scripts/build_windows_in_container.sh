#!/bin/bash
set -euo pipefail

mkdir -p dist/windows
rm -rf dist/windows/pyinstaller-work
rm -f dist/windows/N-AI.exe dist/windows/N-AI-Setup.exe dist/windows/SETUP.txt

xvfb-run -a wine Z:\\opt\\python311\\python.exe -m PyInstaller \
    --clean \
    --noconfirm \
    --onefile \
    --noconsole \
    --name N-AI \
    --distpath Z:\\workspace\\dist\\windows \
    --workpath Z:\\workspace\\dist\\windows\\pyinstaller-work \
    --specpath Z:\\workspace\\dist\\windows \
    --paths Z:\\workspace \
    --hidden-import windows.overlay \
    --hidden-import windows.capture_exclusion \
    --collect-all sounddevice \
    --collect-all _sounddevice_data \
    Z:\\workspace\\backend\\main.py

cat > dist/windows/SETUP.txt <<'SETUP'
N-AI setup

1. Double-click N-AI-Setup.exe and follow the installer prompts.
2. Allow microphone access if Windows asks.
3. Click the key icon in N-AI, paste your OpenAI API key, then choose Save key.
   The key is stored locally in %APPDATA%\N-AI\.env.
4. Restart N-AI after saving the key.

The installer does not include an API key. The installer and app are unsigned.
SETUP

makensis scripts/windows_installer.nsi

test -s dist/windows/N-AI.exe
test -s dist/windows/N-AI-Setup.exe
printf 'Created dist/windows/N-AI.exe and dist/windows/N-AI-Setup.exe\n'
