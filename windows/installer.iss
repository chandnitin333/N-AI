#define AppName "N-AI"
#define AppVersion "1.0.0"
#define AppPublisher "N-AI"
#define AppExeName "N-AI.exe"

[Setup]
AppId={{BB6B31E0-D89C-48EE-A1C7-D48542C2AC93}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\N-AI
DefaultGroupName={#AppName}
OutputDir=..\dist\windows
OutputBaseFilename=N-AI-Setup
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\dist\windows\N-AI.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\windows\SETUP.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\N-AI"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\N-AI"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch N-AI"; Flags: postinstall nowait skipifsilent
