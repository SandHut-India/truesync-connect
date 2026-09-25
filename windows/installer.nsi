Unicode true
!include "MUI2.nsh"
Name "TrueSync Connector"
OutFile "../dist/TrueSync-Connector-Windows.exe"
InstallDir "$LOCALAPPDATA\Programs\TrueSync Connector"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Icon "../TrueSync.Connector/TrueSync.ico"
UninstallIcon "../TrueSync.Connector/TrueSync.ico"
VIProductVersion "0.1.2.0"
VIAddVersionKey "ProductName" "TrueSync Connector"
VIAddVersionKey "FileDescription" "TrueSync Connector Setup"
VIAddVersionKey "FileVersion" "0.1.2"
VIAddVersionKey "LegalCopyright" "Copyright (c) 2026 SandHut and Nandakishore Gowda G"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "Install TrueSync Connector to connect your shop's printers to TrueSync.$\r$\n$\r$\nInstalls for your Windows account. No separate .NET installation is needed."
!define MUI_FINISHPAGE_RUN "$INSTDIR\TrueSync Connector.exe"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!macro CheckRunning
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\TrueSyncConnector") p.r0'
  StrCmp $0 0 ready
  System::Call 'kernel32::CloseHandle(p r0)'
  MessageBox MB_OK|MB_ICONEXCLAMATION "Please exit TrueSync Connector from its system tray menu, then run this installer again."
  Abort
  ready:
!macroend
Function .onInit
  SetShellVarContext current
  !insertmacro CheckRunning
FunctionEnd
Function un.onInit
  SetShellVarContext current
  !insertmacro CheckRunning
FunctionEnd
Section "Install"
  SetOutPath "$INSTDIR"
  File /r "../dist/win-x64/*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\TrueSync Connector.lnk" "$INSTDIR\TrueSync Connector.exe"
  CreateShortcut "$DESKTOP\TrueSync Connector.lnk" "$INSTDIR\TrueSync Connector.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "DisplayName" "TrueSync Connector"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "DisplayVersion" "0.1.2"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "Publisher" "SandHut"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "DisplayIcon" "$INSTDIR\TrueSync Connector.exe"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector" "NoRepair" 1
SectionEnd
Section "Uninstall"
  !include "../dist/uninstall-files.nsh"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\TrueSync Connector.lnk"
  Delete "$DESKTOP\TrueSync Connector.lnk"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "TrueSyncConnector"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector"
  MessageBox MB_OK "TrueSync Connector was removed. Remove this computer in TrueSync > Printers to revoke its connection. Your pairing settings are retained for reinstalling."
SectionEnd
