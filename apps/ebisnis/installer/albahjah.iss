; Inno Setup script for the Al-Bahjah POS Windows variant.
; AppVersion is passed in via /DAppVersion=x.y.z on the ISCC command line.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6C9E2D4-6C3A-4B0E-9C0D-1E3A5F0ALBH}
AppName=Al-Bahjah POS
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\Al-Bahjah POS
DefaultGroupName=Al-Bahjah POS
UninstallDisplayIcon={app}\ebisnis_albahjah.exe
OutputBaseFilename=Al-Bahjah-POS-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_albahjah.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
; Exclude exe varian LAIN juga (ebisnis_inventory_sales.exe bisa tersisa dari build varian
; Inventory & Sales di folder Release yang sama -- copy_if_different tidak menghapus).
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis.exe,ebisnis_inventory_sales.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Al-Bahjah POS"; Filename: "{app}\ebisnis_albahjah.exe"
Name: "{group}\Uninstall Al-Bahjah POS"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Al-Bahjah POS"; Filename: "{app}\ebisnis_albahjah.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_albahjah.exe"; Description: "Jalankan Al-Bahjah POS sekarang"; Flags: nowait postinstall skipifsilent

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
