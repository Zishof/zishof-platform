; Inno Setup script for the Sarimpi Jaya Frozen Windows variant.
; AppVersion is passed in via /DAppVersion=x.y.z on the ISCC command line.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{F702E4F0-5A31-48C9-9A2E-8F1A0B2FROZEN}
AppName=Sarimpi Jaya Frozen POS
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\Sarimpi Jaya Frozen POS
DefaultGroupName=Sarimpi Jaya Frozen POS
UninstallDisplayIcon={app}\ebisnis_frozenfood.exe
OutputBaseFilename=Sarimpi-Jaya-Frozen-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_frozenfood.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis.exe,ebisnis_albahjah.exe,ebisnis_inventory_sales.exe,ebisnis_apotik.exe,ebisnis_emedik.exe,ebisnis_nahl.exe,ebisnis_petra.exe,ebisnis_mitrainap.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\ebisnis_frozenfood.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Sarimpi Jaya Frozen POS"; Filename: "{app}\ebisnis_frozenfood.exe"
Name: "{group}\Uninstall Sarimpi Jaya Frozen POS"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Sarimpi Jaya Frozen POS"; Filename: "{app}\ebisnis_frozenfood.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_frozenfood.exe"; Description: "Jalankan Sarimpi Jaya Frozen POS sekarang"; Flags: nowait postinstall skipifsilent

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
