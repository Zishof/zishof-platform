; Inno Setup script for the eKantin Petra Windows variant.
; AppVersion is passed in via /DAppVersion=x.y.z on the ISCC command line.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{C4F1A9E7-3D82-4A16-95B7-2E6C0D7PETRA}
AppName=eKantin Petra
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\eKantin Petra
DefaultGroupName=eKantin Petra
UninstallDisplayIcon={app}\ebisnis_petra.exe
OutputBaseFilename=eKantin-Petra-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
; Ikon installer masih memakai ikon eBisnis. Ganti ke icon_petra.ico setelah
; logo asli UKP tersedia (lihat assets/images/petra/BACA-DULU.txt).
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
; Exclude exe varian LAIN: folder Release dipakai bergantian antar varian dan
; copy_if_different tidak menghapus exe varian sebelumnya.
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis.exe,ebisnis_albahjah.exe,ebisnis_inventory_sales.exe,ebisnis_apotik.exe,ebisnis_emedik.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\ebisnis_petra.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\eKantin Petra"; Filename: "{app}\ebisnis_petra.exe"
Name: "{group}\Uninstall eKantin Petra"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eKantin Petra"; Filename: "{app}\ebisnis_petra.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_petra.exe"; Description: "Jalankan eKantin Petra sekarang"; Flags: nowait postinstall skipifsilent

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
