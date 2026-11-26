# Sloppy portable configuration. Pure path/schema/IO helpers; no WPF, no network.
$ErrorActionPreference = 'Stop'

# Captured at dot-source time so the root stays tied to this file even when the
# function is called from the WPF shell or a Pester container.
$script:SlopConfigFileRoot = $PSScriptRoot
$script:SlopConfigVersion = 3
$script:SlopIdentityColors = @{
    ocean = '#6366F1'
    moss  = '#14B8A6'
    plum  = '#A855F7'
    ember = '#EC4899'
    sky   = '#38BDF8'
    stone = '#94A3B8'
}
$script:SlopBrains = @('builtin', 'custom', 'opencode')
$script:SlopPersonalities = @('calm', 'playful', 'curious', 'professional')
$script:SlopCapabilityProfiles = @('companion', 'workspace', 'power')

function Get-SlopAppRoot {
    # Hidden CI/headless isolation only. Never surfaced in the UI or docs as a
    # user feature.
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_INSTALL_ROOT)) {
        return [IO.Path]::GetFullPath($env:SLOP_TEST_INSTALL_ROOT)
    }
    if ($script:SlopConfigFileRoot) {
        return [IO.Path]::GetFullPath((Join-Path $script:SlopConfigFileRoot '..'))
    }
    throw 'Cannot resolve the Sloppy app root'
}

function Get-SlopUserDataPath { return Join-Path (Get-SlopAppRoot) 'data' }
function Get-SlopConfigPath    { return Join-Path (Get-SlopUserDataPath) 'config.json' }
function Get-SlopPersonaPath   { return Join-Path (Get-SlopUserDataPath) 'persona.md' }
function Get-SlopIdentityColors { return @{} + $script:SlopIdentityColors }
function Get-SlopPersonalities  { return @($script:SlopPersonalities) }
function Get-SlopBrains         { return @($script:SlopBrains) }
function Get-SlopCapabilityProfiles { return @($script:SlopCapabilityProfiles) }
function Get-SlopIdentityColor {
    param([Parameter(Mandatory)][string]$ColorKey)
    if (-not $script:SlopIdentityColors.ContainsKey($ColorKey)) { throw "unknown identity color: $ColorKey" }
    return $script:SlopIdentityColors[$ColorKey]
}

function Test-SlopLoopbackHttpUrl {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'http' -or -not $uri.IsLoopback) { return $false }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) { return $false }
    return $true
}

function New-SlopDefaultConfig {
    return @{
        version           = $script:SlopConfigVersion
        name              = 'Sloppy'
        ownerName         = 'friend'
        color             = 'ocean'
        personality       = 'calm'
        instructions      = 'Be concise, honest, and helpful.'
        brain             = 'builtin'
        endpointUrl       = 'http://127.0.0.1:11434'
        modelName         = 'Qwen3.5-2B Q4_K_M'
        autostart         = $true

        # Tier 1 bundled local brain (Qwen3.5-2B Q4_K_M). Readiness flags stay
        # hooks; Tier 1 voice resolves through Slop.Audio.ps1 paths.
        localModelName    = 'Qwen3.5-2B Q4_K_M'
        localModelFile    = 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf'
        localMmprojFile   = ''
        localContextSize  = 8192
        localVisionReady  = $true
        localAudioReady   = $true

        # Tier 1 voice input, opt-in and local only.
        voiceEnabled      = $false
        whisperRuntimeFile = 'runtime\whisper\whisper-cli.exe'
        whisperModelFile   = 'runtime\whisper\models\ggml-small.bin'
        whisperLanguage    = 'auto'
        voiceMaxSeconds    = 30

        # Tier 2 route fields. Locality is a preference; disclosure is driven by
        # observed endpoint evidence, not by a stored price label.
        provider          = 'opencode'
        providerLocality  = ''
        capabilityProfile = 'companion'
        agentId           = 'sloppy'
        model             = 'big-pickle'
        agent             = @{}
        openCodeBaseUrl   = 'http://127.0.0.1:28894'
        serviceConfigPath = ''
        openCodeSessionId = ''
    }
}

function Get-SlopBrainOrder { return @('builtin', 'opencode', 'custom') }

function Get-SlopBrainModelOptions {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Brain)
    switch ([string]$Brain) {
        'builtin'  { return @('Qwen3.5-2B Q4_K_M') }
        'opencode' { return @('big-pickle', 'beam-free') }
        default    { return @() }
    }
}

function Resolve-SlopTier {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Brain)
    switch ([string]$Brain) {
        'builtin'  { return 1 }
        'opencode' { return 2 }
        default    { return 0 }
    }
}

function Get-SlopAutostartValue {
    param([Parameter(Mandatory)][string]$ExecutablePath)
    return '"' + ($ExecutablePath -replace '"', '\"') + '"'
}

function Test-SlopConfig {
    param([Parameter(Mandatory)][hashtable]$Config)
    $errors = [Collections.Generic.List[string]]::new()
    if ($Config.version -isnot [int] -or $Config.version -lt 1 -or $Config.version -gt $script:SlopConfigVersion) {
        $errors.Add('version is unsupported')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config.name) -or ([string]$Config.name).Length -gt 40) {
        $errors.Add('name must be 1-40 characters')
    }
    if (([string]$Config.ownerName).Length -gt 40) { $errors.Add('ownerName must be at most 40 characters') }
    if ($Config.ContainsKey('instructions') -and ([string]$Config.instructions).Length -gt 1200) { $errors.Add('instructions must be at most 1200 characters') }
    if (-not $script:SlopIdentityColors.ContainsKey([string]$Config.color)) { $errors.Add('color is not an identity swatch') }
    if ($script:SlopPersonalities -notcontains [string]$Config.personality) { $errors.Add('personality preset is unknown') }
    if ($script:SlopBrains -notcontains [string]$Config.brain) { $errors.Add('brain choice is unknown') }
    if (([string]$Config.modelName).Length -gt 120) { $errors.Add('modelName is too long') }
    if ($Config.brain -eq 'custom') {
        if (-not (Test-SlopLoopbackHttpUrl -Url ([string]$Config.endpointUrl))) {
            $errors.Add('endpointUrl must be a local http URL')
        }
    }
    if ($Config.autostart -isnot [bool]) { $errors.Add('autostart must be a boolean') }

    # Route fields: keep them bounded and enumerable so a tampered config cannot
    # silently escalate a route or a capability profile.
    if ([string]$Config.providerLocality -notin @('', 'local', 'remote')) {
        $errors.Add('providerLocality must be local or remote')
    }
    if ($script:SlopCapabilityProfiles -notcontains [string]$Config.capabilityProfile) {
        $errors.Add('capabilityProfile is unknown')
    }
    if (([string]$Config.provider).Length -gt 80) { $errors.Add('provider is too long') }
    if (([string]$Config.model).Length -gt 120) { $errors.Add('model is too long') }
    if (([string]$Config.localModelName).Length -gt 120) { $errors.Add('localModelName is too long') }
    if (([string]$Config.localModelFile).Length -gt 260) { $errors.Add('localModelFile is too long') }
    if (([string]$Config.localMmprojFile).Length -gt 260) { $errors.Add('localMmprojFile is too long') }
    if (@(8192, 16384, 32768) -notcontains [int]$Config.localContextSize) { $errors.Add('localContextSize must be 8192, 16384, or 32768') }
    if ($Config.localVisionReady -isnot [bool]) { $errors.Add('localVisionReady must be a boolean') }
    if ($Config.localAudioReady -isnot [bool]) { $errors.Add('localAudioReady must be a boolean') }
    if ($Config.voiceEnabled -isnot [bool]) { $errors.Add('voiceEnabled must be a boolean') }
    if ([string]::IsNullOrWhiteSpace([string]$Config.whisperRuntimeFile) -or ([string]$Config.whisperRuntimeFile).Length -gt 260) {
        $errors.Add('whisperRuntimeFile must be 1-260 characters')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config.whisperModelFile) -or ([string]$Config.whisperModelFile).Length -gt 260) {
        $errors.Add('whisperModelFile must be 1-260 characters')
    }
    if ([string]$Config.whisperLanguage -cnotmatch '^(auto|[a-z]{2,3})$') {
        $errors.Add('whisperLanguage must be auto or a lowercase 2-3 letter code')
    }
    if ($Config.voiceMaxSeconds -isnot [int] -or [int]$Config.voiceMaxSeconds -lt 10 -or [int]$Config.voiceMaxSeconds -gt 120) {
        $errors.Add('voiceMaxSeconds must be an integer between 10 and 120')
    }
    if (([string]$Config.agentId).Length -gt 80) { $errors.Add('agentId is too long') }
    if (([string]$Config.serviceConfigPath).Length -gt 260) { $errors.Add('serviceConfigPath is too long') }
    if (([string]$Config.openCodeBaseUrl).Length -gt 260) { $errors.Add('openCodeBaseUrl is too long') }
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.openCodeBaseUrl) -and
        -not (Test-SlopLoopbackHttpUrl -Url ([string]$Config.openCodeBaseUrl))) {
        $errors.Add('openCodeBaseUrl must be a loopback http URL without embedded credentials or query data')
    }
    if (([string]$Config.openCodeSessionId).Length -gt 120) { $errors.Add('openCodeSessionId is too long') }
    if ($null -ne $Config.agent -and $Config.agent -isnot [hashtable]) { $errors.Add('agent must be a hashtable') }

    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Read-SlopConfig {
    param([string]$ConfigPath = (Get-SlopConfigPath))
    $defaults = New-SlopDefaultConfig
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return @{ Ok = $true; Exists = $false; Config = $defaults; Reason = $null }
    }
    try { $raw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
    catch { return @{ Ok = $false; Exists = $true; Config = $defaults; Reason = 'config.json is not valid JSON' } }

    # Unknown keys are ignored. Missing known keys take defaults. Pre-v3 configs
    # (version 0/1/2/absent) migrate to version 3 before validation.
    $cfg = @{}
    foreach ($key in $defaults.Keys) {
        $cfg[$key] = if ($raw.PSObject.Properties[$key]) { $raw.$key } else { $defaults[$key] }
    }
    # Version 0/1/2 configs are pre-v3 shapes. Normalize numeric JSON values to
    # [int] before validation because ConvertFrom-Json emits [long].
    if ($cfg.version -is [int] -or $cfg.version -is [long]) { $cfg.version = [int]$cfg.version }
    else { $cfg.version = 3 }
    if ($cfg.version -lt 3) {
        # v2 carried providerTier=free|paid. The $cfg loop above copies only v3
        # default keys, so the legacy value lives on $raw (the parsed JSON) and
        # MUST be read from there. Drop the price label; a paid remote choice
        # still resolves to the same observed remote route.
        $legacyTier = $raw.PSObject.Properties['providerTier']
        if ($null -ne $legacyTier -and [string]$legacyTier.Value -eq 'paid' -and
            [string]::IsNullOrWhiteSpace([string]$cfg.providerLocality)) {
            $cfg.providerLocality = 'remote'
        }
        $cfg.version = 3
    }
    if ([string]$cfg.brain -eq 'builtin' -or [string]$cfg.brain -eq 'custom' -or [string]$cfg.brain -eq 'opencode') {
        # normalise JSON booleans and strings without accepting arbitrary values
        $cfg.autostart = [bool]$cfg.autostart
    }
    # Local bundled brain readiness hooks: keep backward-compatible defaults and
    # normalize invalid enum/bool values to safe defaults.
    $allowedLocalCtx = @(8192, 16384, 32768)
    if ($allowedLocalCtx -notcontains [int]$cfg.localContextSize) { $cfg.localContextSize = 8192 }
    $cfg.localVisionReady = [bool]$cfg.localVisionReady
    $cfg.localAudioReady = [bool]$cfg.localAudioReady
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localModelName)) { $cfg.localModelName = $defaults.localModelName }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localModelFile)) { $cfg.localModelFile = $defaults.localModelFile }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.localMmprojFile)) { $cfg.localMmprojFile = $defaults.localMmprojFile }
    # Voice keys are new in version 2. Existing values win; malformed values fall
    # back to the safe default rather than locking the user out of the app.
    if ($cfg.voiceEnabled -isnot [bool]) { $cfg.voiceEnabled = $defaults.voiceEnabled }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.whisperRuntimeFile)) { $cfg.whisperRuntimeFile = $defaults.whisperRuntimeFile }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.whisperModelFile)) { $cfg.whisperModelFile = $defaults.whisperModelFile }
    if ([string]$cfg.whisperLanguage -cnotmatch '^(auto|[a-z]{2,3})$') { $cfg.whisperLanguage = $defaults.whisperLanguage }
    if ($cfg.voiceMaxSeconds -is [int] -or $cfg.voiceMaxSeconds -is [long]) {
        $cfg.voiceMaxSeconds = [int]$cfg.voiceMaxSeconds
    }
    else { $cfg.voiceMaxSeconds = 30 }
    if ($cfg.voiceMaxSeconds -lt 10 -or $cfg.voiceMaxSeconds -gt 120) { $cfg.voiceMaxSeconds = 30 }
    # A JSON object for 'agent' arrives as PSCustomObject; the route resolver
    # only needs hashtable-style member access, so normalise it explicitly.
    if ($cfg.agent -isnot [hashtable]) {
        $agent = @{}
        if ($null -ne $cfg.agent) {
            foreach ($prop in $cfg.agent.PSObject.Properties) { $agent[$prop.Name] = $prop.Value }
        }
        $cfg.agent = $agent
    }
    $check = Test-SlopConfig -Config $cfg
    if (-not $check.Ok) {
        return @{ Ok = $false; Exists = $true; Config = $defaults; Reason = ($check.Errors -join '; ') }
    }
    return @{ Ok = $true; Exists = $true; Config = $cfg; Reason = $null }
}

function Write-SlopConfig {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$ConfigPath = (Get-SlopConfigPath)
    )
    $check = Test-SlopConfig -Config $Config
    if (-not $check.Ok) { throw "refusing to write invalid config: $($check.Errors -join '; ')" }
    $dir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path -LiteralPath $ConfigPath) {
        Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.bak" -Force
    }
    $tmp = "$ConfigPath.tmp"
    [IO.File]::WriteAllText($tmp, ($Config | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp, $ConfigPath, $true)
}

function Read-SlopPersona {
    param([string]$PersonaPath = (Get-SlopPersonaPath))
    if (Test-Path -LiteralPath $PersonaPath) { return Get-Content -LiteralPath $PersonaPath -Raw }
    return ''
}
function Write-SlopPersona {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$PersonaPath = (Get-SlopPersonaPath)
    )
    $dir = Split-Path -Parent $PersonaPath
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path -LiteralPath $PersonaPath) {
        Copy-Item -LiteralPath $PersonaPath -Destination "$PersonaPath.bak" -Force
    }
    [IO.File]::WriteAllText($PersonaPath, $Text, [Text.UTF8Encoding]::new($false))
}

function Set-SlopConfigIdentity {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Color,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Personality
    )
    $candidate = @{} + $Config
    $candidate.name = ([string]$Name).Trim()
    $candidate.color = ([string]$Color).Trim().ToLowerInvariant()
    $candidate.personality = ([string]$Personality).Trim().ToLowerInvariant()
    $check = Test-SlopConfig -Config $candidate
    return @{
        Ok     = [bool]$check.Ok
        Config = $candidate
        Errors = @($check.Errors)
    }
}

function Set-SlopConfigBrain {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Brain,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ProviderLocality,
        [Parameter(Mandatory)][AllowEmptyString()][string]$EndpointUrl,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Model,
        [Parameter(Mandatory)][AllowEmptyString()][string]$AgentId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CapabilityProfile
    )
    $candidate = @{} + $Config
    $errors = [Collections.Generic.List[string]]::new()
    $modelValue = ([string]$Model).Trim()

    $candidate.brain = ([string]$Brain).Trim().ToLowerInvariant()
    $candidate.provider = ([string]$Provider).Trim()
    $candidate.providerLocality = ([string]$ProviderLocality).Trim().ToLowerInvariant()
    $candidate.endpointUrl = ([string]$EndpointUrl).Trim().TrimEnd('/')
    $candidate.model = $modelValue
    $candidate.modelName = $modelValue
    $candidate.agentId = ([string]$AgentId).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate.agentId)) { $candidate.agentId = 'sloppy' }
    $candidate.capabilityProfile = ([string]$CapabilityProfile).Trim().ToLowerInvariant()
    $candidate.agent = @{}

    if ($candidate.brain -notin @('builtin', 'custom', 'opencode')) {
        $errors.Add('brain choice is unknown')
    }
    switch ($candidate.brain) {
        'builtin' {
            $candidate.provider = ''
            $candidate.providerLocality = ''
            $candidate.endpointUrl = ''
            $candidate.model = ''
            $candidate.modelName = ''
        }
        'custom' {
            $candidate.provider = ''
            $candidate.providerLocality = ''
            $candidate.agentId = 'sloppy'
            $candidate.capabilityProfile = 'companion'
            if ([string]::IsNullOrWhiteSpace($modelValue)) { $errors.Add('custom model is required') }
        }
        'opencode' {
            $candidate.endpointUrl = ''
            if ([string]::IsNullOrWhiteSpace($modelValue)) { $errors.Add('opencode model is required') }
        }
    }

    $check = Test-SlopConfig -Config $candidate
    foreach ($message in $check.Errors) { $errors.Add($message) }
    return @{
        Ok     = ($errors.Count -eq 0)
        Config = $candidate
        Errors = $errors.ToArray()
    }
}
