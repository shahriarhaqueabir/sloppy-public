# S.L.O.P. process control: one implementation behind the startslop / stopslop
# aliases in PowerShell, bash and zsh. The password is never written to disk by
# this script — it is read from the environment or from OpenCode's own persisted
# service config, and only prompted for as a last resort.
param(
    [Parameter(Mandatory)][ValidateSet('Start','Stop','Status')][string]$Action
)
$ErrorActionPreference = 'Stop'

$Repo = Split-Path $PSScriptRoot -Parent
$App = Join-Path $Repo 'src/Slop.ps1'

function Get-SlopProcesses {
    # Match the script path, not 'slop-control.ps1', and accept either separator.
    @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -match 'src[/\\]Slop\.ps1' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
}

function Test-SlopOwnedBrainCommandLine {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$CommandLine,
        [Parameter(Mandatory)][string]$Repo
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    if ($CommandLine -notmatch '--alias\s+sloppy(?:\s|$)') { return $false }
    $root = [IO.Path]::GetFullPath($Repo).TrimEnd('\', '/')
    foreach ($sep in @('\', '/')) {
        $prefix = $root + $sep + 'runtime' + $sep
        if ($CommandLine.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-SlopBrainProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" |
        Where-Object { Test-SlopOwnedBrainCommandLine -CommandLine ([string]$_.CommandLine) -Repo $Repo } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
}

function Get-OpenCodeBaseUrl {
    try {
        $line = @(& opencode service status 2>$null | Where-Object { $_ -match '^https?://' })[0]
        if ($line) { return [string]$line }
    } catch { }
    return $null
}

function Wait-OpenCodeService {
    param([int]$Attempts = 20, [int]$DelayMs = 250)
    for ($i = 0; $i -lt $Attempts; $i++) {
        $url = Get-OpenCodeBaseUrl
        if ($url) { return $url }
        Start-Sleep -Milliseconds $DelayMs
    }
    return $null
}

function Get-SlopServiceConfigPath {
    # SLOP_SERVICE_CONFIG is a test hook; production uses OpenCode's own store.
    if ($env:SLOP_SERVICE_CONFIG) { return $env:SLOP_SERVICE_CONFIG }
    return Join-Path $env:USERPROFILE '.config/opencode/service.json'
}

function Get-SlopOpenCodePassword {
    if (-not [string]::IsNullOrEmpty($env:OPENCODE_PASSWORD)) { return $env:OPENCODE_PASSWORD }

    $configPath = Get-SlopServiceConfigPath
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if (-not [string]::IsNullOrEmpty($config.password)) { return [string]$config.password }
        } catch { }
    }

    $masked = Read-Host -MaskInput 'OPENCODE_PASSWORD (opencode serve password)'
    if ([string]::IsNullOrEmpty($masked)) { throw 'OPENCODE_PASSWORD is required' }
    return [Net.NetworkCredential]::new('', $masked).Password
}

function Test-SlopShouldInstallFallbackConfig {
    param([string]$CurrentConfig)
    # A user's active OpenCode config always wins. Only an empty service env
    # means "nothing set up", which is when the bundled minimal config is used.
    return [string]::IsNullOrWhiteSpace($CurrentConfig)
}

function Sync-SlopOpenCodeConfig {
    # OpenCode's shared service owns agent discovery. Never overwrite a config
    # the user already has active. If none exists, install the bundled minimal
    # zero-trust config so Sloppy still works on a fresh setup.
    $configPath = Join-Path $Repo '.opencode/opencode.jsonc'
    $current = ''
    try { $current = ((& opencode service get env OPENCODE_CONFIG_CONTENT 2>$null | Out-String) -replace "`r`n", "`n").Trim() } catch { }
    if (-not (Test-SlopShouldInstallFallbackConfig -CurrentConfig $current)) { return $false }
    if (-not (Test-Path $configPath)) { return $false }

    # The service normalizes CRLF to LF when it returns an env value, so normalize
    # the bundled config the same way before writing it.
    $desired = ((Get-Content $configPath -Raw) -replace "`r`n", "`n").Trim()

    # `opencode service set env` STOPS the managed service (verified on v2.3.2:
    # status reports "stopped" immediately and 1.5s after the call). The caller
    # must start it again; nothing here restarts it implicitly.
    Push-Location $Repo
    try { & opencode service set env OPENCODE_CONFIG_CONTENT $desired | Out-Host } finally { Pop-Location }
    return $true
}

function Test-OpenCodeAuth {
    param([string]$BaseUrl, [string]$Password)
    if (-not $BaseUrl) { return $false }
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("opencode:$Password"))
    try {
        $response = Invoke-WebRequest "$BaseUrl/api/info" -UseBasicParsing `
            -Headers @{ Authorization = "Basic $token" } -TimeoutSec 5
        return ($response.StatusCode -eq 200)
    } catch { return $false }
}

switch ($Action) {
    'Status' {
        $svc = Get-OpenCodeBaseUrl
        if ($svc) { "OpenCode: $svc" } else { 'OpenCode: not running' }
        $procs = Get-SlopProcesses
        if ($procs.Count) { "Slop: running (PID $($procs.Id -join ', '))" } else { 'Slop: stopped' }
    }
    'Start' {
        $live = Get-SlopProcesses
        if ($live.Count) {
            "Slop already running (PID $($live.Id -join ', '))"
            return
        }
        if (-not (Test-Path $App)) { throw "Slop app not found: $App" }

        # Resolve the password before starting anything, so a background service
        # inherits the same credential the app will use.
        $password = Get-SlopOpenCodePassword
        $env:OPENCODE_PASSWORD = $password

        $svc = Get-OpenCodeBaseUrl
        if (-not $svc) {
            Write-Host 'OpenCode service is down; starting it from the repo root...'
            Push-Location $Repo
            try { & opencode service start | Out-Host } finally { Pop-Location }
            $svc = Wait-OpenCodeService
            if (-not $svc) { throw 'OpenCode service did not start' }
        }

        if (Sync-SlopOpenCodeConfig) {
            # set env stopped the service, so bring it back before using the URL.
            Push-Location $Repo
            try { & opencode service start | Out-Host } finally { Pop-Location }
            $svc = Wait-OpenCodeService
            if (-not $svc) { throw 'OpenCode service did not return after config sync' }
        }

        if (-not (Test-OpenCodeAuth -BaseUrl $svc -Password $password)) {
            throw "OpenCode rejected the persisted password. Run 'opencode service restart' so the service picks up $(Get-SlopServiceConfigPath)."
        }

        $pwsh = (Get-Command pwsh).Source
        $proc = Start-Process -FilePath $pwsh `
            -ArgumentList @('-STA','-NoProfile','-File', ('"' + $App + '"')) `
            -WindowStyle Hidden -PassThru
        # Hide the console host so only the WPF pea window appears on the taskbar.
        # (Without this, pwsh opens a stray console window behind Slop.)
        "Slop started (PID $($proc.Id))"
    }
    'Stop' {
        $procs = @(Get-SlopProcesses) + @(Get-SlopBrainProcesses)
        if (-not $procs.Count) { 'Slop is not running'; return }
        foreach ($p in $procs) {
            $id = $p.Id
            try {
                if ($p.CloseMainWindow()) {
                    if (-not $p.WaitForExit(5000)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
                }
                else { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
                "Slop stopped (PID $id)"
            }
            catch { "Could not stop PID ${id}: $($_.Exception.Message)" }
        }
        # The OpenCode service is shared; leave it alone. Use `opencode service stop`.
    }
}
