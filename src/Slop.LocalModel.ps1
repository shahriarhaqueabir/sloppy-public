# Bundled llama.cpp lifecycle. Headless: process/argument helpers and HTTP health only.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopAppRoot -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Slop.Config.ps1')
}
$script:SlopModelPort = 18080
$script:SlopAllowedContextSizes = @(8192, 16384, 32768)

function Get-SlopAllowedContextSizes { return @($script:SlopAllowedContextSizes) }

function Resolve-SlopLocalContextSize {
    param([int]$ContextSize = 8192)
    if ($script:SlopAllowedContextSizes -contains [int]$ContextSize) { return [int]$ContextSize }
    return 8192
}

function Get-SlopBundledModelName { return 'Qwen3.5-2B Q4_K_M' }

function Resolve-SlopRuntimeFilePath {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$File,
        [Parameter(Mandatory)][string]$DefaultRelativePath
    )
    $value = if ([string]::IsNullOrWhiteSpace($File)) { $DefaultRelativePath } else { $File.Trim() }
    if ([IO.Path]::IsPathRooted($value)) { return [IO.Path]::GetFullPath($value) }
    return [IO.Path]::GetFullPath((Join-Path $InstallRoot $value))
}

function Get-SlopRuntimePaths {
    param(
        [string]$InstallRoot = (Get-SlopAppRoot),
        [AllowEmptyString()][string]$ModelFile = 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf',
        [AllowEmptyString()][string]$MmprojFile = ''
    )
    $resolvedMmproj = ''
    if (-not [string]::IsNullOrWhiteSpace($MmprojFile)) {
        # File is non-empty here, so Resolve-SlopRuntimeFilePath never falls back
        # to DefaultRelativePath; passing the same value keeps the mandatory
        # parameter satisfied without allowing an empty mandatory string.
        $resolvedMmproj = Resolve-SlopRuntimeFilePath -InstallRoot $InstallRoot -File $MmprojFile -DefaultRelativePath $MmprojFile
    }
    # Pick the best available bundled runtime: prefer CUDA when an NVIDIA GPU is
    # present, otherwise fall back to the CPU build so Tier 1 works on any PC.
    $cudaExe = Join-Path $InstallRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe'
    $cpuExe  = Join-Path $InstallRoot 'runtime\llama-b12676-bin-win-cpu-x64\llama-server.exe'
    $hasNvidia = $false
    try { if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { $hasNvidia = $true } } catch { }
    if (-not $hasNvidia) {
        try { $hasNvidia = [bool](Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' }) } catch { }
    }
    $serverExe = if ($hasNvidia -and (Test-Path -LiteralPath $cudaExe)) { $cudaExe }
                 elseif (Test-Path -LiteralPath $cpuExe) { $cpuExe }
                 else { $cudaExe }
    return @{
        InstallRoot = $InstallRoot
        ServerExe   = $serverExe
        ModelFile   = (Resolve-SlopRuntimeFilePath -InstallRoot $InstallRoot -File $ModelFile -DefaultRelativePath 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf')
        MmprojFile  = $resolvedMmproj
        Port        = $script:SlopModelPort
        BaseUrl     = "http://127.0.0.1:$script:SlopModelPort"
    }
}

function Test-SlopLocalModelPaths {
    param([Parameter(Mandatory)][hashtable]$Paths)
    $errors = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Paths.ServerExe)) { $errors.Add('the built-in brain is missing llama-server.exe') }
    elseif ((Get-Item -LiteralPath $Paths.ServerExe).Length -lt 1KB) {
        $errors.Add('llama-server.exe is a Git LFS pointer; run "git lfs pull" in the Sloppy folder')
    }
    if (-not (Test-Path -LiteralPath $Paths.ModelFile)) { $errors.Add('the built-in brain model file is missing') }
    elseif ((Get-Item -LiteralPath $Paths.ModelFile).Length -lt 1KB) {
        $errors.Add('the model file is a Git LFS pointer; run "git lfs pull" in the Sloppy folder')
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Paths.MmprojFile) -and
        -not (Test-Path -LiteralPath $Paths.MmprojFile)) {
        $errors.Add('the built-in brain mmproj file is missing')
    }
    if ($Paths.Port -lt 1024 -or $Paths.Port -gt 65535) { $errors.Add('the local model port is invalid') }
    return @{ Ok = ($errors.Count -eq 0); Reason = ($errors -join '; ') }
}

function New-SlopLlamaArguments {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [int]$Threads = 0,
        [int]$ContextSize = 8192,
        [int]$MaxTokens = 512
    )
    if ($Threads -le 0) { $Threads = [Environment]::ProcessorCount - 2 }
    $Threads = [Math]::Max(2, [Math]::Min(8, $Threads))
    $ContextSize = Resolve-SlopLocalContextSize -ContextSize $ContextSize
    $llamaArgs = [Collections.Generic.List[string]]::new()
    $llamaArgs.Add('--model')
    $llamaArgs.Add([string]$Paths.ModelFile)
    if (-not [string]::IsNullOrWhiteSpace([string]$Paths.MmprojFile)) {
        $llamaArgs.Add('--mmproj')
        $llamaArgs.Add([string]$Paths.MmprojFile)
    }
    $llamaArgs.Add('--jinja')
    $llamaArgs.Add('--host')
    $llamaArgs.Add('127.0.0.1')
    $llamaArgs.Add('--port')
    $llamaArgs.Add([string]$Paths.Port)
    $llamaArgs.Add('--ctx-size')
    $llamaArgs.Add([string]$ContextSize)
    $llamaArgs.Add('--cache-ram')
    $llamaArgs.Add('0')
    $llamaArgs.Add('--threads')
    $llamaArgs.Add([string]$Threads)
    $llamaArgs.Add('--n-predict')
    $llamaArgs.Add([string]$MaxTokens)
    $llamaArgs.Add('--alias')
    $llamaArgs.Add('sloppy')
    return $llamaArgs.ToArray()
}

function Test-SlopLocalModelHealth {
    param([Parameter(Mandatory)][string]$BaseUrl, [int]$TimeoutMs = 1000)
    $uri = $null
    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'http' -or -not $uri.IsLoopback) {
        return @{ Ok = $false; Reason = 'local model health URL must be loopback http' }
    }
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -TimeoutSec ([Math]::Max(1, [int]($TimeoutMs / 1000))) -UseBasicParsing
        return @{ Ok = ($resp.StatusCode -eq 200); Reason = $null }
    }
    catch { return @{ Ok = $false; Reason = $_.Exception.Message } }
}

function Test-SlopOwnedModelProcess {
    param([Parameter(Mandatory)][hashtable]$Paths, [System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return $false }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return $false }
        $actualPath = [IO.Path]::GetFullPath($Process.MainModule.FileName)
        $expectedPath = [IO.Path]::GetFullPath($Paths.ServerExe)
        if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($Process.Id)" -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$processInfo.CommandLine) -or
            $processInfo.CommandLine.IndexOf([string]$Paths.ModelFile, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }

        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Paths.Port -ErrorAction SilentlyContinue)
        if (@($listeners | Where-Object {
            $_.OwningProcess -eq $Process.Id -and $_.LocalAddress -in @('127.0.0.1','::1')
        }).Count -eq 0) { return $false }
        return (Test-SlopLocalModelHealth -BaseUrl $Paths.BaseUrl -TimeoutMs 1000).Ok
    }
    catch { return $false }
}

function Test-SlopPortAvailable {
    param([Parameter(Mandatory)][int]$Port)
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch { return $false }
    finally { if ($listener) { $listener.Stop() } }
}

function Get-SlopOwnedModelProcessOnPort {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [object[]]$Connections,
        [scriptblock]$ProcessResolver,
        [scriptblock]$Verifier
    )
    if ($null -eq $Connections) {
        $Connections = @(Get-NetTCPConnection -State Listen -LocalPort $Paths.Port -ErrorAction SilentlyContinue)
    }
    if (-not $ProcessResolver) {
        $ProcessResolver = { param($id) Get-Process -Id $id -ErrorAction SilentlyContinue }
    }
    if (-not $Verifier) {
        $Verifier = { param($process) Test-SlopOwnedModelProcess -Paths $Paths -Process $process }
    }
    $ownerIds = @($Connections | Where-Object {
        $_ -and $_.OwningProcess -gt 0 -and $_.LocalAddress -in @('127.0.0.1','::1')
    } | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($id in $ownerIds) {
        $process = & $ProcessResolver $id
        if ($null -eq $process) { continue }
        if (& $Verifier $process) { return $process }
    }
    return $null
}

function Start-SlopLocalModel {
    # This readiness loop may wait up to 90 seconds. Call it from a worker, never
    # from the WPF dispatcher thread.
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [System.Diagnostics.Process]$Process,
        [int]$ContextSize = 8192,
        [int]$WaitSeconds = 90
    )
    $pre = Test-SlopLocalModelPaths -Paths $Paths
    if (-not $pre.Ok) { return @{ Ok = $false; Reason = $pre.Reason; Process = $null } }
    if ($Process) {
        if (Test-SlopOwnedModelProcess -Paths $Paths -Process $Process) {
            return @{ Ok = $true; Reason = $null; Process = $Process }
        }
        return @{ Ok = $false; Reason = 'the existing local brain is no longer the Sloppy-owned model process; restart the brain before continuing'; Process = $null }
    }
    if (-not (Test-SlopPortAvailable -Port $Paths.Port)) {
        $adopted = Get-SlopOwnedModelProcessOnPort -Paths $Paths
        if ($adopted) {
            return @{ Ok = $true; Reason = $null; Process = $adopted }
        }
        return @{ Ok = $false; Reason = 'another program is using the local brain port; Sloppy will not send prompts to an unverified local service'; Process = $null }
    }
    $ContextSize = Resolve-SlopLocalContextSize -ContextSize $ContextSize
    $llamaArgs = New-SlopLlamaArguments -Paths $Paths -ContextSize $ContextSize
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Paths.ServerExe
    $startInfo.WorkingDirectory = Split-Path -Parent $Paths.ServerExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($arg in $llamaArgs) { [void]$startInfo.ArgumentList.Add([string]$arg) }
    try { $proc = [Diagnostics.Process]::Start($startInfo) }
    catch { return @{ Ok = $false; Reason = 'the built-in brain could not be started; check the installed runtime and try again'; Process = $null } }
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($proc.HasExited) {
            return @{ Ok = $false; Reason = 'the built-in brain stopped while starting; close other apps to free memory and try again'; Process = $null }
        }
        if ((Test-SlopOwnedModelProcess -Paths $Paths -Process $proc)) {
            return @{ Ok = $true; Reason = $null; Process = $proc }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    return @{ Ok = $false; Reason = 'the built-in brain took too long to wake; close other apps and try again'; Process = $null }
}

function Stop-SlopLocalModel {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process -or $Process.HasExited) { return }
    Stop-Process -Id $Process.Id -Force
}

function Format-SlopLocalModelFailure {
    param([Parameter(Mandatory)][string]$Reason)
    if ($Reason -match 'memory|resource|out of memory') {
        return 'There is not enough free memory. Close a few apps or use Sleep model in the tray, then try again.'
    }
    return "$Reason You can change brains any time from the tray."
}
