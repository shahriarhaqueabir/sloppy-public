<#
.SYNOPSIS
  Downloads and runs the single-folder Sloppy installer.
.DESCRIPTION
  One behavior for the double-click installer and the PowerShell one-liner.
  With -InstallDir the wizard is suppressed; without it the Inno folder picker
  is shown. -DesktopShortcut opts into the otherwise-unchecked desktop task.
.EXAMPLE
  $installer = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1
  & ([scriptblock]::Create($installer)) -InstallDir 'D:\Sloppy' -DesktopShortcut
#>
param(
    [string]$InstallDir,
    [switch]$DesktopShortcut,
    [string]$ReleaseTag = 'v0.3.0'
)
$ErrorActionPreference = 'Stop'

$base = 'https://github.com/shahriarhaqueabir/Sloppy/releases/download/' + $ReleaseTag
$setupUrl = $base + '/SloppySetup.exe'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('sloppy-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$setup = Join-Path $temp 'SloppySetup.exe'

try {
    Write-Host 'Downloading the Sloppy installer...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $setupUrl -OutFile $setup -UseBasicParsing

    $argsList = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $argsList.Add('/DIR="' + [IO.Path]::GetFullPath($InstallDir) + '"')
        $argsList.Add('/VERYSILENT')
        $argsList.Add('/SUPPRESSMSGBOXES')
    }
    if ($DesktopShortcut) { $argsList.Add('/TASKS=desktopicon') }
    else { $argsList.Add('/TASKS=') }

    $proc = Start-Process -FilePath $setup -ArgumentList $argsList.ToArray() -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Sloppy setup exited with code $($proc.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
