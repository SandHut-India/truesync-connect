Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
Name "TrueSync Connector"
OutFile "../dist/TrueSync-Connector-Windows.exe"
InstallDir "$LOCALAPPDATA\Programs\TrueSync Connector"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Icon "../TrueSync.Connector/TrueSync.ico"
UninstallIcon "../TrueSync.Connector/TrueSync.ico"
!define VERSION "0.1.4"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrueSyncConnector"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "TrueSync Connector"
VIAddVersionKey "CompanyName" "SandHut"
VIAddVersionKey "FileDescription" "TrueSync Connector Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
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
  IfSilent 0 ask
  ; Silent installs (Microsoft Store updates) cannot prompt. The result journal prevents reprinting a claimed job.
  nsExec::Exec 'taskkill /F /IM "TrueSync Connector.exe"'
  Pop $1
  Sleep 1500
  Goto ready
  ask:
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
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "TrueSync Connector"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "SandHut"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\TrueSync Connector.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://truesync-2026.web.app/"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "HelpLink" "https://github.com/SandHut-India/truesync-connect"
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" "$0"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd
Section "Uninstall"
  !include "../dist/uninstall-files.nsh"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\TrueSync Connector.lnk"
  Delete "$DESKTOP\TrueSync Connector.lnk"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "TrueSyncConnector"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  RMDir /r "$LOCALAPPDATA\TrueSyncConnector"
  MessageBox MB_OK "TrueSync Connector was removed from this computer. Also remove it in TrueSync > Printers to revoke its connection." /SD IDOK
SectionEnd
