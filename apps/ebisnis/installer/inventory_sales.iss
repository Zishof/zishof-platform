; Inno Setup script for the eBisnis Inventory & Sales Windows variant.
; AppVersion is passed in via /DAppVersion=x.y.z on the ISCC command line.
;
; Build exe-nya lebih dulu (WAJIB kedua parameter, lihat lib/main_inventory_sales.dart):
;   flutter build windows --release -t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales
; Release/ akan berisi ebisnis.exe + salinan ebisnis_inventory_sales.exe (pola sama albahjah.iss);
; installer ini meng-exclude ebisnis.exe supaya folder instalasi hanya berisi exe varian ini.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6C9E2D4-6C3A-4B0E-9C0D-1E3A5F0INVSL}
AppName=eBisnis Inventory & Sales
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\eBisnis Inventory & Sales
DefaultGroupName=eBisnis Inventory & Sales
UninstallDisplayIcon={app}\ebisnis_inventory_sales.exe
OutputBaseFilename=eBisnis-Inventory-Sales-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_inventory_sales.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
; Folder Release bisa berisi sisa exe varian lain (copy_if_different tidak pernah
; menghapus, dan varian baru terus bertambah: albahjah/apotik/emedik/...). Exclude
; SEMUA ebisnis*.exe lalu masukkan kembali HANYA exe varian ini -- future-proof,
; tidak perlu memperbarui daftar tiap kali ada varian baru.
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis*.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\ebisnis_inventory_sales.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\eBisnis Inventory & Sales"; Filename: "{app}\ebisnis_inventory_sales.exe"
Name: "{group}\Uninstall eBisnis Inventory & Sales"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eBisnis Inventory & Sales"; Filename: "{app}\ebisnis_inventory_sales.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis_inventory_sales.exe"; Description: "Jalankan eBisnis Inventory & Sales sekarang"; Flags: nowait postinstall skipifsilent

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
