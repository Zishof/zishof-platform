; Inno Setup script for the standalone Apotik Windows variant.
; AppVersion is passed in via /DAppVersion=x.y.z on the ISCC command line.
;
; Build exe-nya lebih dulu (WAJIB kedua parameter, lihat lib/main_apotik.dart):
;   flutter build windows --release -t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik
; Release/ akan berisi ebisnis.exe + salinan ebisnis_apotik.exe (pola sama albahjah.iss);
; installer ini meng-exclude ebisnis.exe + exe varian lain (sisa copy_if_different build
; varian sebelumnya) supaya folder instalasi hanya berisi exe varian ini.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6C9E2D4-6C3A-4B0E-9C0D-1E3A5F0APTIK}
AppName=Apotik
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\Apotik
DefaultGroupName=Apotik
UninstallDisplayIcon={app}\ebisnis_apotik.exe
OutputBaseFilename=eBisnis-POS-Apotik-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_apotik.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis.exe,ebisnis_albahjah.exe,ebisnis_inventory_sales.exe,ebisnis_emedik.exe,ebisnis_petra.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Apotik"; Filename: "{app}\ebisnis_apotik.exe"
Name: "{group}\Uninstall Apotik"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Apotik"; Filename: "{app}\ebisnis_apotik.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_apotik.exe"; Description: "Jalankan Apotik sekarang"; Flags: nowait postinstall skipifsilent

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
