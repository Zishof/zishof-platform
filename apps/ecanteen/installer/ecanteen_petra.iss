; Inno Setup script untuk eCanteen varian Petra (Windows).
; Bangun dulu dgn --dart-define=ECANTEEN_VARIANT=petra supaya nama di dalam
; aplikasi ikut varian, lalu jalankan ISCC dgn /DAppVersion=x.y.z.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; AppId BERBEDA dari varian umum supaya keduanya bisa terpasang berdampingan
; dan tidak saling meng-uninstall.
AppId={{4C8D1F62-77B3-49AE-B25C-6E0F3A1PETRA}
AppName=Direktorat Pengembangan Usaha Sosial
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\eKantin Petra
DefaultGroupName=eKantin Petra
UninstallDisplayIcon={app}\zishof.exe
OutputBaseFilename=eCanteen-Petra-Setup-{#AppVersion}
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
Source: "..\..\ebisnis\installer\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\eKantin Petra"; Filename: "{app}\zishof.exe"
Name: "{group}\Uninstall eKantin Petra"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eKantin Petra"; Filename: "{app}\zishof.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\zishof.exe"; Description: "Jalankan sekarang"; Flags: nowait postinstall skipifsilent

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
