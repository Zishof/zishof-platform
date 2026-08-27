; Inno Setup script for the Al-Bahjah An-Nahl POS Windows variant.
; Build first:
;   flutter build windows --release -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{A11BAA7A-4E41-4A41-8A11-202608270001}
AppName=FF (Fajrul Falah) Mart
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\FF (Fajrul Falah) Mart
DefaultGroupName=FF (Fajrul Falah) Mart
UninstallDisplayIcon={app}\ebisnis_nahl.exe
OutputBaseFilename=FF-Fajrul-Falah-Mart-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_nahl.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis*.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\ebisnis_nahl.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\FF (Fajrul Falah) Mart"; Filename: "{app}\ebisnis_nahl.exe"
Name: "{group}\Uninstall FF (Fajrul Falah) Mart"; Filename: "{uninstallexe}"
Name: "{autodesktop}\FF (Fajrul Falah) Mart"; Filename: "{app}\ebisnis_nahl.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_nahl.exe"; Description: "Jalankan FF (Fajrul Falah) Mart sekarang"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistNeeded: Boolean;
var
  installed: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', installed) then
  begin
    if installed = 1 then
      Result := False;
  end;
end;
