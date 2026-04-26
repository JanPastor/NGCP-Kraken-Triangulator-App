; installer.iss — Inno Setup Script for KrakenSDR Triangulator
; ================================================================
; Produces a professional Windows installer with:
;   - Start Menu shortcut
;   - Desktop shortcut
;   - Add/Remove Programs entry
;   - Optional post-install launch
;
; Prerequisites:
;   1. Build the PyInstaller distribution first:
;      pyinstaller kraken_triangulator.spec --clean --noconfirm
;   2. Install Inno Setup 6: https://jrsoftware.org/isdl.php
;   3. Compile this script:
;      "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
;
; Output: Output/KrakenSDR-Triangulator-Setup-v1.7.0.exe

#define MyAppName "KrakenSDR Triangulator"
#define MyAppVersion "1.7.0"
#define MyAppPublisher "NGCP — Northrop Grumman Collaboration Project"
#define MyAppURL "https://github.com/JanPastor/NGCP-Kraken-Triangulator-App"
#define MyAppExeName "KrakenSDR-Triangulator.exe"

[Setup]
AppId={{8F2E4B6A-1D3C-4A5E-9B7F-0C8D2E6F4A1B}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName=NGCP\{#MyAppName}
AllowNoIcons=yes
; Output installer to the Output/ directory
OutputDir=Output
OutputBaseFilename=KrakenSDR-Triangulator-Setup-v{#MyAppVersion}
; Compression settings for a small installer
Compression=lzma2/ultra64
SolidCompression=yes
; Require Windows 10+
MinVersion=10.0
; Installer appearance
WizardStyle=modern
; Icon (use the app's icon if available)
; SetupIconFile=app\favicon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Bundle the entire PyInstaller output directory
Source: "dist\KrakenSDR-Triangulator\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
