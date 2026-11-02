$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildEnv = Join-Path $ProjectRoot ".build-venv"
$OutputDir = Join-Path $ProjectRoot "dist\windows"

if (-not $IsWindows -and $env:OS -ne "Windows_NT") {
    throw "Build the Windows installer on Windows."
}

$Python = (Get-Command py -ErrorAction SilentlyContinue)
if ($Python) {
    & py -3 -m venv $BuildEnv
} else {
    & python -m venv $BuildEnv
}
if ($LASTEXITCODE -ne 0) { throw "Could not create the build environment." }

$BuildPython = Join-Path $BuildEnv "Scripts\python.exe"
& $BuildPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "Could not update pip." }
& $BuildPython -m pip install -r (Join-Path $ProjectRoot "requirements-build.txt")
if ($LASTEXITCODE -ne 0) { throw "Could not install build dependencies." }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
& $BuildPython -m PyInstaller --clean --noconfirm --onefile --noconsole `
    --name N-AI --distpath $OutputDir `
    --workpath (Join-Path $OutputDir "pyinstaller-work") `
    --specpath $OutputDir `
    --paths $ProjectRoot `
    --hidden-import windows.overlay --hidden-import windows.capture_exclusion `
    --collect-all sounddevice --collect-all _sounddevice_data `
    (Join-Path $ProjectRoot "backend\main.py")
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed." }

@'
N-AI setup

1. Run N-AI-Setup.exe and follow the installer.
2. On first launch, Windows may ask for microphone access. Allow it.
3. Click the key icon in N-AI, paste your OpenAI API key, then choose Save key.
   The key is stored locally in %APPDATA%\N-AI\.env.
4. Restart N-AI after saving the key.

The installer does not include an API key. For public distribution, sign the
installer and app executable with your publisher certificate.
'@ | Set-Content -Encoding UTF8 (Join-Path $OutputDir "SETUP.txt")

$Compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $Compiler) {
    throw "Install Inno Setup 6 and make ISCC.exe available on PATH, then rerun this script."
}
& $Compiler.Source (Join-Path $ProjectRoot "windows\installer.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed." }

Write-Host "Created $(Join-Path $OutputDir 'N-AI-Setup.exe')"
