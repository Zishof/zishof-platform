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
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis_albahjah.exe,ebisnis_inventory_sales.exe,ebisnis_apotik.exe,ebisnis_emedik.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft Visual C++ 2015-2022 Redistributable (x64) -- WAJIB, Flutter Windows release
; build TIDAK static-link MSVC runtime, jadi ebisnis.exe gagal start di Windows fresh-install
; dgn "VCRUNTIME140.dll was not found" (gap-closure: sebelumnya pengguna harus unduh+pasang
; manual sendiri). Diekstrak ke {tmp} (bukan {app}) -- cuma dipakai sekali sbg installer,
; tak perlu menetap di folder aplikasi.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\eBisnis"; Filename: "{app}\ebisnis.exe"
Name: "{group}\Uninstall eBisnis"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eBisnis"; Filename: "{app}\ebisnis.exe"; Tasks: desktopicon

[Run]
; /install /quiet /norestart -- silent, tak butuh interaksi kasir. Digerbang VCRedistNeeded
; (cek registry) supaya TIDAK dijalankan ulang di mesin yg sudah punya runtime ini (kebanyakan
; Windows 10/11 modern sudah punya bawaan) -- hemat ~30-60 detik waktu instal per rilis.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\ebisnis.exe"; Description: "Jalankan eBisnis sekarang"; Flags: nowait postinstall skipifsilent

[Code]
// Deteksi Visual C++ 2015-2022 Redistributable (x64) via kunci registry resmi yg dipasang
// installer Microsoft (Installed=1 + Bld menunjukkan versi build runtime terpasang).
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
