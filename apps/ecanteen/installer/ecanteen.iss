; Inno Setup script untuk aplikasi member eCanteen (Windows).
; AppVersion dikirim lewat /DAppVersion=x.y.z pada baris perintah ISCC.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{7E2B5A31-9C44-4D07-8F16-3A9D2C0ECANT}
AppName=eCanteen
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\eCanteen
DefaultGroupName=eCanteen
UninstallDisplayIcon={app}\zishof.exe
OutputBaseFilename=eCanteen-Setup-{#AppVersion}
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
; eCanteen dibangun di direktori build sendiri (apps/ecanteen), jadi tidak ada
; exe varian lain yang perlu dikecualikan seperti pada installer eBisnis.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Runtime VC++ dipakai bersama dgn installer eBisnis -- tidak disalin ke repo
; lagi supaya biner 18 MB tidak terduplikasi.
Source: "..\..\ebisnis\installer\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\eCanteen"; Filename: "{app}\zishof.exe"
Name: "{group}\Uninstall eCanteen"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eCanteen"; Filename: "{app}\zishof.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\zishof.exe"; Description: "Jalankan eCanteen sekarang"; Flags: nowait postinstall skipifsilent

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
