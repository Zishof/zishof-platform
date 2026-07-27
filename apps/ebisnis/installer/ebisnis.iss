; Inno Setup script -- packages the Flutter Windows release build into a proper
; installer (Setup.exe), mirroring what electron-builder/NSIS produced for the
; old Electron app: installs to Program Files, adds a Start Menu shortcut +
; optional desktop icon, registers an uninstaller, and can launch the app on
; finish. Not hand-maintained per release -- AppVersion is passed in via
; /DAppVersion=x.y.z on the ISCC command line so it always matches pubspec.yaml.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6C9E2D4-6C3A-4B0E-9C0D-1E3A5F0EBISN}
AppName=eBisnis
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\eBisnis
DefaultGroupName=eBisnis
UninstallDisplayIcon={app}\ebisnis.exe
OutputBaseFilename=eBisnis-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\eBisnis"; Filename: "{app}\ebisnis.exe"
Name: "{group}\Uninstall eBisnis"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eBisnis"; Filename: "{app}\ebisnis.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ebisnis.exe"; Description: "Jalankan eBisnis sekarang"; Flags: nowait postinstall skipifsilent
