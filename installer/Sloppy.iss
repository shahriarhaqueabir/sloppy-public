; Single-folder Sloppy installer. Compile with Inno Setup 6.5.4+.
; GUI: double-click SloppySetup.exe.
; CLI: SloppySetup.exe /DIR="D:\Sloppy" /TASKS=desktopicon /VERYSILENT
; install.ps1 maps -InstallDir to /DIR= and -DesktopShortcut to /TASKS=desktopicon.
#define MyAppName "Sloppy"
#define MyAppVersion "0.3.0"
#define MyAppPublisher "shahriarhaqueabir"
#define MyAppExeName "run.vbs"
#define MyAppId "{{B8E1A0C4-6D4E-4A4B-9C7B-2F1E0D3A5B71}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Sloppy
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=..\artifacts
OutputBaseFilename=SloppySetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableDirPage=no
UninstallDisplayName={#MyAppName} {#MyAppVersion}
AllowNoIcons=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Dirs]
Name: "{app}\data"; Flags: uninsneveruninstall

[Files]
Source: "..\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\llama-b12676-bin-win-cpu-x64\*"; DestDir: "{app}\runtime\llama-b12676-bin-win-cpu-x64"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\llama-b12676-bin-win-cuda-13.5-x64\*"; DestDir: "{app}\runtime\llama-b12676-bin-win-cuda-13.5-x64"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\whisper\*"; DestDir: "{app}\runtime\whisper"; Excludes: "models\ggml-small.bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\run.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\run.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"
Name: "{autodesktop}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon

[Code]
function SlopJsonString(const S: String): String;
var
  T: String;
begin
  { Backslash is not an escape character in Pascal string literals. }
  T := S;
  StringChangeEx(T, '\', '\\', True);
  StringChangeEx(T, '"', '\"', True);
  Result := '"' + T + '"';
end;

function Get-PreviousSlopInstallRoot(out Root: String): Boolean;
var
  Key: String;
begin
  Result := False;
  Root := '';
  { ISPP emits {{GUID}; ExpandConstant collapses it to the real {GUID} key. }
  Key := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}_is1');
  if RegQueryStringValue(HKCU, Key, 'InstallLocation', Root) then
    Result := DirExists(Root)
  else if RegQueryStringValue(HKLM, Key, 'InstallLocation', Root) then
    Result := DirExists(Root);
end;

function Locate-SlopPowerShell: String;
var
  Candidate: String;
begin
  Result := '';
  { FileSearch is an Inno support function. }
  Candidate := FileSearch('pwsh.exe', GetEnv('Path'));
  if Candidate <> '' then
  begin
    Result := Candidate;
    Exit;
  end;
  Candidate := AddBackslash(GetEnv('ProgramFiles')) + 'PowerShell\7\pwsh.exe';
  if FileExists(Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;
  Candidate := AddBackslash(GetEnv('LOCALAPPDATA')) + 'Programs\PowerShell\7\pwsh.exe';
  if FileExists(Candidate) then Result := Candidate;
end;

function Ensure-SlopPowerShell: Boolean;
var
  ResultCode: Integer;
begin
  if Locate-SlopPowerShell <> '' then
  begin
    Result := True;
    Exit;
  end;
  if not Exec('winget.exe',
              'install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements',
              '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := False;
    Exit;
  end;
  Result := Locate-SlopPowerShell <> '';
end;

procedure Write-SlopInstallMarker;
var
  Marker: String;
  Previous: String;
begin
  Marker := AddBackslash(ExpandConstant('{app}')) + '.sloppy-install.json';
  if Get-PreviousSlopInstallRoot(Previous) then
    SaveStringToFile(Marker,
      '{ "version": 1, "appVersion": ' + SlopJsonString('{#MyAppVersion}') +
      ', "root": ' + SlopJsonString(ExpandConstant('{app}')) +
      ', "upgradedFrom": ' + SlopJsonString(Previous) + ' }', False)
  else
    SaveStringToFile(Marker,
      '{ "version": 1, "appVersion": ' + SlopJsonString('{#MyAppVersion}') +
      ', "root": ' + SlopJsonString(ExpandConstant('{app}')) + ' }', False);
end;

procedure Fetch-SlopAssets;
var
  PowerShellExe: String;
  Params: String;
  ResultCode: Integer;
begin
  PowerShellExe := Locate-SlopPowerShell;
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
            AddBackslash(ExpandConstant('{app}')) + 'tools\slop-fetch-assets.ps1" -InstallRoot "' +
            ExpandConstant('{app}') + '" -ManifestPath "' +
            AddBackslash(ExpandConstant('{app}')) + 'tools\slop-assets.json"';
  if not Exec(PowerShellExe, Params, ExpandConstant('{app}'), SW_HIDE,
              ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    raise Exception.Create('Sloppy could not download its models. Check your connection and re-run setup.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not Ensure-SlopPowerShell then
      raise Exception.Create('Sloppy needs PowerShell 7.6 or newer. Install it, then re-run setup.');
  end;
  if CurStep = ssPostInstall then
  begin
    Write-SlopInstallMarker;
    Fetch-SlopAssets;
  end;
end;
