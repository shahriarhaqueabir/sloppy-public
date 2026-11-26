# Bundled Whisper transcription helpers. Headless: no WPF, no network, no registry.
#requires -Version 7.6
$ErrorActionPreference = 'Stop'

$script:SlopWhisperModelSha1 = '55356645c2b361a969dfd0ef2c5a50d530afd8d5'
$script:SlopWhisperExecutableExtensions = @('.exe', '.cmd', '.bat')

function Get-SlopWhisperLanguages {
    return @('auto', 'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'zh')
}

function Get-SlopVoiceInstallRoot {
    param([string]$InstallRoot)
    if (-not (Get-Command Get-SlopAppRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Slop.Config.ps1')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_INSTALL_ROOT)) {
        return [IO.Path]::GetFullPath($env:SLOP_TEST_INSTALL_ROOT)
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        return [IO.Path]::GetFullPath($InstallRoot)
    }
    return Get-SlopAppRoot
}

function Get-SlopVoiceReadinessText {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$InstallRoot = (Get-SlopVoiceInstallRoot)
    )
    $paths = Get-SlopWhisperPaths -InstallRoot $InstallRoot `
        -CliFile ([string]$Config.whisperRuntimeFile) -ModelFile ([string]$Config.whisperModelFile)
    $ready = Test-SlopWhisperReady -Paths $paths
    if ($ready.Ok) { return 'Ready' }
    return ($ready.Errors -join '; ')
}

function Get-SlopWhisperPaths {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CliFile,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ModelFile
    )
    $cli = if ([IO.Path]::IsPathRooted($CliFile)) { $CliFile } else { Join-Path $InstallRoot $CliFile }
    $model = if ([IO.Path]::IsPathRooted($ModelFile)) { $ModelFile } else { Join-Path $InstallRoot $ModelFile }
    return @{
        Cli   = [IO.Path]::GetFullPath($cli)
        Model = [IO.Path]::GetFullPath($model)
    }
}

function Test-SlopWhisperReady {
    param([Parameter(Mandatory)][hashtable]$Paths)

    $errors = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace([string]$Paths.Cli)) {
        $errors.Add('whisperRuntimeFile is empty')
    }
    elseif (-not (Test-Path -LiteralPath $Paths.Cli -PathType Leaf)) {
        $errors.Add("whisperRuntimeFile is missing: $($Paths.Cli)")
    }
    else {
        $ext = [IO.Path]::GetExtension([string]$Paths.Cli)
        if ($script:SlopWhisperExecutableExtensions -notcontains $ext) {
            $errors.Add("whisperRuntimeFile must be an executable file: $($Paths.Cli)")
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Paths.Model)) {
        $errors.Add('whisperModelFile is empty')
    }
    elseif (-not (Test-Path -LiteralPath $Paths.Model -PathType Leaf)) {
        $errors.Add("whisperModelFile is missing: $($Paths.Model)")
    }

    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Test-SlopWhisperIntegrity {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [string]$ExpectedSha1 = $script:SlopWhisperModelSha1
    )
    if (-not (Test-Path -LiteralPath $Paths.Model -PathType Leaf)) {
        return @{ Ok = $false; Expected = $ExpectedSha1; Actual = $null; Reason = "whisperModelFile is missing: $($Paths.Model)" }
    }
    $actual = (Get-FileHash -LiteralPath $Paths.Model -Algorithm SHA1).Hash.ToLowerInvariant()
    $ok = ($actual -eq $ExpectedSha1.ToLowerInvariant())
    return @{
        Ok       = $ok
        Expected = $ExpectedSha1.ToLowerInvariant()
        Actual   = $actual
        Reason   = if ($ok) { '' } else { "whisperModelFile has the wrong SHA-1: $($Paths.Model)" }
    }
}

function Convert-SlopWhisperOutput {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)
    $lines = @(
        $Raw -split '\r?\n' |
            ForEach-Object { ($_ -replace '^\s*\[[^\]]+\]\s*', '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    return ($lines -join ' ')
}

function Invoke-SlopWhisperTranscription {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][string]$WavPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Language,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
    )

    $ready = Test-SlopWhisperReady -Paths $Paths
    if (-not $ready.Ok) {
        return @{ Ok = $false; Text = ''; Reason = ($ready.Errors -join '; '); ExitCode = $null }
    }

    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("slop-whisper-out-" + [guid]::NewGuid().ToString('N') + '.txt')
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("slop-whisper-err-" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $argList = @(
            '-m', ('"' + $Paths.Model + '"')
            '-f', ('"' + $WavPath + '"')
            '-l', $Language
            '-nt', '-np'
            '-t', '4'
        )
        $process = Start-Process -FilePath $Paths.Cli -ArgumentList $argList -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
            return @{ Ok = $false; Text = ''; Reason = "whisper-cli timed out after $TimeoutSeconds seconds"; ExitCode = $null }
        }
        $process.WaitForExit()
        $raw = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $text = Convert-SlopWhisperOutput -Raw $raw
        if ($process.ExitCode -ne 0) {
            $stderr = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw).Trim() } else { '' }
            $reason = if ($stderr) { "whisper-cli exited $($process.ExitCode): $stderr" } else { "whisper-cli exited $($process.ExitCode)" }
            return @{ Ok = $false; Text = ''; Reason = $reason; ExitCode = $process.ExitCode }
        }
        return @{ Ok = $true; Text = $text; Reason = ''; ExitCode = 0 }
    }
    catch {
        return @{ Ok = $false; Text = ''; Reason = $_.Exception.Message; ExitCode = $null }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}
