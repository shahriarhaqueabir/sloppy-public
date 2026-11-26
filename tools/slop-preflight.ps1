# Headless Tier 1 readiness report. Never downloads, never writes user config.
#requires -Version 7.6
param(
    [string]$InstallRoot,
    [string]$ConfigPath,
    [string]$ExpectedModelSha1,
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
. (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
. (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')

function Invoke-SlopPreflight {
    param(
        [string]$InstallRoot,
        [string]$ConfigPath,
        [string]$ExpectedModelSha1
    )
    $root = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { Get-SlopAppRoot } else { [IO.Path]::GetFullPath($InstallRoot) }
    $cfgPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Get-SlopConfigPath } else { $ConfigPath }
    $lines = [Collections.Generic.List[string]]::new()
    $errors = [Collections.Generic.List[string]]::new()

    $configResult = Read-SlopConfig -ConfigPath $cfgPath
    if ($configResult.Ok) {
        $cfg = $configResult.Config
        $configText = if ($configResult.Exists) {
            "config version $($cfg.version), voiceEnabled=$($cfg.voiceEnabled), whisperLanguage=$($cfg.whisperLanguage), voiceMaxSeconds=$($cfg.voiceMaxSeconds)"
        }
        else {
            "config defaults (not written yet), version $($cfg.version), voiceEnabled=$($cfg.voiceEnabled)"
        }
        $lines.Add("[OK] config: $configText")
    }
    else {
        $errors.Add("config: $($configResult.Reason)")
        $lines.Add("[FAIL] config: $($configResult.Reason)")
        $cfg = New-SlopDefaultConfig
    }

    $modelPaths = Get-SlopRuntimePaths -InstallRoot $root -ModelFile ([string]$cfg.localModelFile) -MmprojFile ([string]$cfg.localMmprojFile)
    $artifacts = @(
        @{ Label = 'llama server'; Path = $modelPaths.ServerExe },
        @{ Label = 'Qwen model'; Path = $modelPaths.ModelFile }
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$modelPaths.MmprojFile)) {
        $artifacts += @{ Label = 'mmproj'; Path = $modelPaths.MmprojFile }
    }
    foreach ($entry in $artifacts) {
        if (Test-Path -LiteralPath $entry.Path -PathType Leaf) { $lines.Add("[OK] $($entry.Label): $($entry.Path)") }
        else {
            $errors.Add("$($entry.Label) is missing: $($entry.Path)")
            $lines.Add("[FAIL] $($entry.Label): $($entry.Path)")
        }
    }

    $whisperPaths = Get-SlopWhisperPaths -InstallRoot $root `
        -CliFile ([string]$cfg.whisperRuntimeFile) -ModelFile ([string]$cfg.whisperModelFile)
    $whisperReady = Test-SlopWhisperReady -Paths $whisperPaths
    if ($whisperReady.Ok) { $lines.Add("[OK] Whisper CLI: $($whisperPaths.Cli)") }
    else {
        $errors.AddRange([string[]]$whisperReady.Errors)
        foreach ($message in $whisperReady.Errors) { $lines.Add("[FAIL] Whisper CLI/model: $message") }
    }

    if (Test-Path -LiteralPath $whisperPaths.Model -PathType Leaf) {
        $integrityParams = @{ Paths = $whisperPaths }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedModelSha1)) { $integrityParams.ExpectedSha1 = $ExpectedModelSha1 }
        $integrity = Test-SlopWhisperIntegrity @integrityParams
        if ($integrity.Ok) { $lines.Add("[OK] Whisper model SHA-1: $($integrity.Actual)") }
        else {
            $errors.Add($integrity.Reason)
            $lines.Add("[FAIL] Whisper model SHA-1: expected $($integrity.Expected), got $($integrity.Actual)")
        }
    }

    return @{ Ok = ($errors.Count -eq 0); InstallRoot = $root; Lines = $lines.ToArray(); Errors = $errors.ToArray() }
}

if ($MyInvocation.InvocationName -ne '.') {
    $report = Invoke-SlopPreflight -InstallRoot $InstallRoot -ConfigPath $ConfigPath -ExpectedModelSha1 $ExpectedModelSha1
    $report.Lines | ForEach-Object { Write-Host $_ }
    if (-not $report.Ok -and -not $ReportOnly) { exit 1 }
}
