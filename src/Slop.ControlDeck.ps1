# Pure control deck catalog. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopControlDeckSections {
    return @(
        @{ Name = 'Overview';       Key = 'overview' }
        @{ Name = 'Settings';       Key = 'settings' }
        @{ Name = 'Data';           Key = 'data' }
        @{ Name = 'Tools & Skills'; Key = 'tools' }
        @{ Name = 'Under the hood'; Key = 'underTheHood' }
        @{ Name = 'Exit';           Key = 'exit' }
    )
}

function Get-SlopControlDeckToggleIds {
    return @(
        'WorkspaceFilesToggle'
        'WebAccessToggle'
        'ShellCommandsToggle'
        'SkillsPluginsToggle'
        'SubagentsTasksToggle'
        'ExternalFoldersToggle'
    )
}

function Get-SlopDeckBodyHeight {
    param(
        [Parameter(Mandatory)][double]$WindowHeight,
        [Parameter(Mandatory)][bool]$DeckOpen,
        [double]$FixedHeight = 88.0,
        [double]$OuterMargin = 16.0
    )
    if (-not $DeckOpen) { return 0 }
    $height = $WindowHeight - $FixedHeight - $OuterMargin
    if ($height -le 0) { return 0 }
    return [int][Math]::Floor($height)
}

function Get-SlopDeckExpandedWindowHeight {
    param(
        [Parameter(Mandatory)][double]$WorkAreaHeight,
        [Parameter(Mandatory)][double]$CurrentHeight,
        [double]$PreferredHeight = 620.0
    )
    $wanted = [Math]::Max($PreferredHeight, $CurrentHeight)
    return [int][Math]::Floor([Math]::Min($WorkAreaHeight, $wanted))
}

function Get-SlopDeckSettingsSnapshot {
    param(
        [AllowNull()][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ConfigPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Route,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Readiness
    )
    $available = ($null -ne $Config)
    $voiceEnabled = if ($available) { [bool]$Config.voiceEnabled } else { $false }
    $language = if ($available) { [string]$Config.whisperLanguage } else { '' }
    if ([string]::IsNullOrWhiteSpace($language)) { $language = 'auto' }
    $rawSeconds = if ($available) { $Config['voiceMaxSeconds'] } else { $null }
    $seconds = if ($rawSeconds -is [int] -or $rawSeconds -is [long]) { [int]$rawSeconds } else { 30 }
    if ($seconds -lt 10 -or $seconds -gt 120) { $seconds = 30 }
    $brain = if ($available) { [string]$Config.brain } else { '' }
    if ([string]::IsNullOrWhiteSpace($brain)) { $brain = 'unset' }
    $model = if ($available) { [string]$Config.model } else { '' }
    if ([string]::IsNullOrWhiteSpace($model) -and $available) { $model = [string]$Config.modelName }
    if ([string]::IsNullOrWhiteSpace($model)) { $model = 'unset' }
    $routeText = if ([string]::IsNullOrWhiteSpace($Route)) { 'unset' } else { $Route }
    $readyText = if ([string]::IsNullOrWhiteSpace($Readiness)) { 'unknown' } else { $Readiness }
    $dataPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { 'unavailable' } else { $ConfigPath }
    return @{
        ConfigAvailable = $available
        VoiceEnabled    = $voiceEnabled
        VoiceLanguage   = $language
        VoiceMaxSeconds = $seconds
        VoiceReadyText  = $readyText
        RouteText       = $routeText
        Brain           = $brain
        Model           = $model
        DataPath        = $dataPath
    }
}

function Get-SlopDeckVoiceEdit {
    param(
        [AllowNull()][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Language,
        [Parameter(Mandatory)][AllowEmptyString()][string]$MaxSeconds
    )
    $errors = [Collections.Generic.List[string]]::new()
    if ($null -eq $Config) {
        $errors.Add('Config unavailable.')
        return @{ Ok = $false; Config = $null; Errors = @($errors) }
    }
    $candidate = @{} + $Config
    $language = ([string]$Language).Trim().ToLowerInvariant()
    if ($language -cnotmatch '^(auto|[a-z]{2,3})$') {
        $errors.Add('Language must be auto or a lowercase 2-3 letter code.')
    }
    $seconds = 0
    if (-not [int]::TryParse(([string]$MaxSeconds).Trim(), [ref]$seconds) -or $seconds -lt 10 -or $seconds -gt 120) {
        $errors.Add('Max seconds must be an integer between 10 and 120.')
    }
    $candidate.whisperLanguage = $language
    $candidate.voiceMaxSeconds = $seconds
    return @{ Ok = ($errors.Count -eq 0); Config = $candidate; Errors = @($errors) }
}

function Get-SlopDeckModelEditArguments {
    param(
        [AllowNull()][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Model
    )
    $errors = [Collections.Generic.List[string]]::new()
    $modelValue = ([string]$Model).Trim()
    if ($null -eq $Config) {
        $errors.Add('Config unavailable.')
    } elseif ([string]::IsNullOrWhiteSpace($modelValue)) {
        $errors.Add('Model is required.')
    }
    $brain = if ($null -ne $Config) { [string]$Config.brain } else { '' }
    if ([string]::IsNullOrWhiteSpace($brain)) { $brain = 'builtin' }
    $provider = if ($null -ne $Config) { [string]$Config.provider } else { '' }
    $locality = if ($null -ne $Config) { [string]$Config.providerLocality } else { '' }
    $endpoint = if ($null -ne $Config) { [string]$Config.endpointUrl } else { '' }
    $agent = if ($null -ne $Config) { [string]$Config.agentId } else { '' }
    if ([string]::IsNullOrWhiteSpace($agent)) { $agent = 'sloppy' }
    $profile = if ($null -ne $Config) { [string]$Config.capabilityProfile } else { '' }
    if ([string]::IsNullOrWhiteSpace($profile)) { $profile = 'companion' }
    return @{
        Ok                = ($errors.Count -eq 0)
        Errors            = @($errors)
        Brain             = $brain
        Provider          = $provider
        ProviderLocality  = $locality
        EndpointUrl       = $endpoint
        Model             = $modelValue
        AgentId           = $agent
        CapabilityProfile = $profile
    }
}
