; Engine Builder - NSIS Installer Script
; Compile with: makensis installer.nsi

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "WinCore.nsh"
!include "x64.nsh"

;---------------------------------------------------------------
; General Settings
;---------------------------------------------------------------
!define PROJECT_ROOT "D:\Projects\Engine Builder"
!ifndef PRODUCT_VERSION
!define PRODUCT_VERSION "0.1.5"
!endif
!define OUTPUT_FILE "D:\Projects\Engine Builder\build\installer\EngineBuilder_Setup_${PRODUCT_VERSION}.exe"
Name "Engine Builder"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\Engine Builder"
InstallDirRegKey HKCU "Software\Engine Builder" "Install_Dir"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show
XPStyle on
Unicode true

;---------------------------------------------------------------
; Version Information
;---------------------------------------------------------------
!define PRODUCT_NAME "Engine Builder"
!define PRODUCT_PUBLISHER "Engine Builder Team"
!define PRODUCT_WEB_SITE "https://github.com/engine-builder"
!define PRODUCT_DIR_REGKEY "Software\Engine Builder"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Engine Builder"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"

;---------------------------------------------------------------
; MUI Settings
;---------------------------------------------------------------
!define MUI_WELCOMEPAGE_TITLE "Welcome to the ${PRODUCT_NAME} Setup Wizard"
!define MUI_WELCOMEPAGE_TEXT "This wizard will guide you through the installation of ${PRODUCT_NAME} ${PRODUCT_VERSION}.\n\nClick Next to continue."
!define MUI_FINISHPAGE_TITLE "Completing the ${PRODUCT_NAME} Setup Wizard"
!define MUI_FINISHPAGE_TEXT "Setup has finished installing ${PRODUCT_NAME} ${PRODUCT_VERSION} on your computer.\n\nClick Finish to close this wizard."
!define MUI_FINISHPAGE_RUN "$INSTDIR\EngineBuilder.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"
!define MUI_LICENSEPAGE_TEXT_TOP "Please review the license agreement before installing ${PRODUCT_NAME}."
!define MUI_LICENSEPAGE_TEXT_BOTTOM "If you accept the terms of the agreement, click I Agree to continue. You must accept the agreement to install ${PRODUCT_NAME}."
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select the destination folder for ${PRODUCT_NAME}."
!define MUI_DIRECTORYPAGE_TEXT_DESTINATION "Destination Folder"
!define MUI_INSTFILESPAGE_FINISHHEADER_TEXT "Installation Complete"
!define MUI_INSTFILESPAGE_FINISHTEXT "Click Next to complete the installation."

;---------------------------------------------------------------
; Pages
;---------------------------------------------------------------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Language (must be after page macros)
!insertmacro MUI_LANGUAGE "English"

;---------------------------------------------------------------
; Installer Sections
;---------------------------------------------------------------
Section "MainApplication" SEC_MAIN
  SectionIn RO
  
  ; Set output path
  SetOutPath "$INSTDIR"
  
  ; Copy application files
  File "D:\Projects\Engine Builder\build\windows\EngineBuilder.exe"
  File "D:\Projects\Engine Builder\build\windows\EngineBuilder.pck"
  File "D:\Projects\Engine Builder\build\windows\libengine_sim.windows.template_release.x86_64.dll"
  
  ; Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  
  ; Write registry keys for uninstaller
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "QuietUninstallString" "$INSTDIR\Uninstall.exe /S"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegDWORD ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "NoRepair" 1
  
  ; Store install directory for updates
  WriteRegStr HKCU "${PRODUCT_DIR_REGKEY}" "Install_Dir" "$INSTDIR"
  
  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\Engine Builder"
  CreateShortCut "$SMPROGRAMS\Engine Builder\Engine Builder.lnk" "$INSTDIR\EngineBuilder.exe" "" "$INSTDIR\EngineBuilder.exe" 0
  CreateShortCut "$SMPROGRAMS\Engine Builder\Uninstall.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  
  ; Create Desktop shortcut (optional - user choice)
  CreateShortCut "$DESKTOP\Engine Builder.lnk" "$INSTDIR\EngineBuilder.exe" "" "$INSTDIR\EngineBuilder.exe" 0
  
SectionEnd

;---------------------------------------------------------------
; Uninstaller Section
;---------------------------------------------------------------
Section "Uninstall"
  ; Remove Start Menu shortcuts
  Delete "$SMPROGRAMS\Engine Builder\Engine Builder.lnk"
  Delete "$SMPROGRAMS\Engine Builder\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Engine Builder"
  
  ; Remove Desktop shortcut
  Delete "$DESKTOP\Engine Builder.lnk"
  
  ; Remove application files
  Delete "$INSTDIR\EngineBuilder.exe"
  Delete "$INSTDIR\EngineBuilder.pck"
  Delete "$INSTDIR\Uninstall.exe"
  
  ; Remove install directory
  RMDir "$INSTDIR"
  
  ; Remove registry keys
  DeleteRegKey ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}"
  DeleteRegKey HKCU "${PRODUCT_DIR_REGKEY}"
  
SectionEnd

;---------------------------------------------------------------
; Functions
;---------------------------------------------------------------
Function .onInit
  ; Check for previous installation
  ReadRegStr $0 HKCU "${PRODUCT_DIR_REGKEY}" "Install_Dir"
  StrCmp $0 "" NoPreviousInstall
  
  MessageBox MB_YESNO "A previous version of ${PRODUCT_NAME} is installed at:\n$0\n\nDo you want to uninstall it first?" IDYES UninstallPrevious
  Abort
  
  UninstallPrevious:
  ClearErrors
  ExecWait '"$0\Uninstall.exe" /S'
  IfErrors NoPreviousInstall
  
  NoPreviousInstall:
FunctionEnd

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_OK|MB_ICONINFORMATION "${PRODUCT_NAME} has been successfully uninstalled."
FunctionEnd

;---------------------------------------------------------------
; Reserved Files
;---------------------------------------------------------------
; Place LICENSE.txt in the installer directory
; Place assets/app_icon.ico in the installer directory
; Place assets/installer_banner.bmp in the installer directory (150x570px for MUI2)
