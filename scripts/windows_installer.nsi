Unicode True
ManifestDPIAware True
RequestExecutionLevel user
Name "N-AI"
Caption "N-AI Setup"
OutFile "dist/windows/N-AI-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\N-AI"
InstallDirRegKey HKCU "Software\N-AI" "InstallDir"
ShowInstDetails show
ShowUninstDetails show

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\N-AI.exe"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install N-AI" InstallSection
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File "dist/windows/N-AI.exe"
    File "dist/windows/SETUP.txt"
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    CreateDirectory "$SMPROGRAMS\N-AI"
    CreateShortcut "$SMPROGRAMS\N-AI\N-AI.lnk" "$INSTDIR\N-AI.exe"
    CreateShortcut "$DESKTOP\N-AI.lnk" "$INSTDIR\N-AI.exe"

    WriteRegStr HKCU "Software\N-AI" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\N-AI" "DisplayName" "N-AI"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\N-AI" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\N-AI" "DisplayVersion" "1.0.0"
SectionEnd

Section "Uninstall"
    Delete "$SMPROGRAMS\N-AI\N-AI.lnk"
    RMDir "$SMPROGRAMS\N-AI"
    Delete "$DESKTOP\N-AI.lnk"
    Delete "$INSTDIR\N-AI.exe"
    Delete "$INSTDIR\SETUP.txt"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKCU "Software\N-AI"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\N-AI"
SectionEnd
