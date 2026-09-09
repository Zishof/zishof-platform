; Installer Windows varian AB Chicken. AppVersion dipasok build_semua_varian.ps1.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6B993D8A-E538-49FD-A27F-AB0C11C0A001}
AppName=AB Chicken
AppVersion={#AppVersion}
AppPublisher=Zishof
DefaultDirName={autopf}\AB Chicken
DefaultGroupName=AB Chicken
UninstallDisplayIcon={app}\abchicken.exe
OutputBaseFilename=AB-Chicken-Setup-{#AppVersion}
OutputDir=dist
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\icon_abchicken.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon tambahan:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "ebisnis*.exe,abchicken.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\abchicken.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\AB Chicken"; Filename: "{app}\abchicken.exe"
Name: "{group}\Uninstall AB Chicken"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AB Chicken"; Filename: "{app}\abchicken.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Memasang komponen Microsoft Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\abchicken.exe"; Description: "Jalankan AB Chicken sekarang"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistNeeded: Boolean;
var
  installed: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', installed) then
  begin
    if Installed = 1 then
      Result := False;
  end;
end;
