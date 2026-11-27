# Route taxonomy and badge resolution. Headless: no WPF, no network, no registry.
$ErrorActionPreference = 'Stop'

function Get-SlopRouteCatalog {
    return @{
        'local-bundled'   = @{ Harness='bundled';  Locality='Local';  TermsRequired=$false }
        'custom'          = @{ Harness='Custom';   Locality='Local';  TermsRequired=$false }
        'opencode-local'  = @{ Harness='OpenCode'; Locality='Local';  TermsRequired=$false }
        'opencode-remote' = @{ Harness='OpenCode'; Locality='Remote'; TermsRequired=$true  }
    }
}

function Resolve-SlopRouteKind {
    param([Parameter(Mandatory)][hashtable]$Config)
    if ([string]$Config.brain -eq 'custom') { return 'custom' }
    if ([string]$Config.brain -ne 'opencode') { return 'local-bundled' }
    if ([string]$Config.providerLocality -eq 'local') { return 'opencode-local' }
    return 'opencode-remote'
}

function Resolve-SlopEffectiveModel {
    param(
        [Parameter(Mandatory)][hashtable]$Agent,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $preferred = [string]$Agent.model
    if (-not [string]::IsNullOrWhiteSpace($preferred)) { return $preferred }
    return [string]$Config.model
}

function Get-SlopRouteBadge {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Model
    )
    $catalog = Get-SlopRouteCatalog
    if (-not $catalog.ContainsKey($Kind)) { throw "unknown route kind: $Kind" }
    $entry = $catalog[$Kind]
    return ('{0} · {1} · {2}' -f $entry.Locality, $Provider, $Model)
}

function Get-SlopRoutePlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [object[]]$History = @(),
        [object[]]$Attachments = @(),
        [string]$ObservedProviderEndpointUrl = '',
        [hashtable]$OpenCodePermissionEvidence,
        [System.Diagnostics.Process]$LocalModelProcess,
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    $kind = Resolve-SlopRouteKind -Config $Config
    if ($kind -like 'opencode-*') {
        # Config locality is a preference, not evidence. Until provider discovery
        # supplies the active endpoint, use the remote label and require disclosure.
        $providerUri = $null
        $observedLocal = [Uri]::TryCreate($ObservedProviderEndpointUrl, [UriKind]::Absolute, [ref]$providerUri) -and
            $providerUri.Scheme -in @('http','https') -and $providerUri.IsLoopback -and
            [string]::IsNullOrEmpty($providerUri.UserInfo) -and
            [string]::IsNullOrEmpty($providerUri.Query) -and
            [string]::IsNullOrEmpty($providerUri.Fragment)
        if ($observedLocal) { $kind = 'opencode-local' }
        else { $kind = 'opencode-remote' }
    }
    $catalog = Get-SlopRouteCatalog
    $agent = if ($Config.agent) { $Config.agent } else { @{} }
    $model = Resolve-SlopEffectiveModel -Agent $agent -Config $Config
    $provider = [string]$Config.provider

    if ($kind -eq 'custom') {
        $lifecyclePath = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
        return @{
            Ok=$true; Kind='custom'; StatusText='Waiting for response'
            ReadyToSend=$true
            AdapterPath=(Join-Path $ScriptRootPath 'Slop.Adapter.OpenAi.ps1')
            AdapterArgs=@{
                BaseUrl=([string]$Config.endpointUrl).TrimEnd('/')
                RequestBody=(New-SlopChatRequestBody -SystemPrompt $PersonaText -UserText $UserText -History $History -Attachments $Attachments)
                LifecyclePath=$lifecyclePath; TimeoutSeconds=300
            }
            Badge=(Get-SlopRouteBadge -Kind 'custom' -Provider 'Custom' -Model $model)
            RouteKind='custom'; RequiresDisclosure=$false; PermissionProfile='companion'
        }
    }

    if ($kind -like 'opencode-*') {
        # Permission evidence is ephemeral output of a read-only API probe. It
        # must name this service, agent, provider, model, provider endpoint, and
        # include the active rules, saved grants, and effective policies.
        $baseUrl = if ($Config.openCodeBaseUrl) { [string]$Config.openCodeBaseUrl } else { 'http://127.0.0.1:28894' }
        if (-not (Test-SlopOpenCodeServiceUrl -BaseUrl $baseUrl)) {
            return @{ Ok=$false; Kind=$kind; Reason='OpenCode service must be on this PC over loopback http.' }
        }
        if ([string]::IsNullOrWhiteSpace($provider) -or [string]::IsNullOrWhiteSpace($model) -or
            [string]::IsNullOrWhiteSpace([string]$Config.agentId)) {
            return @{ Ok=$false; Kind=$kind; Reason='Choose an available OpenCode agent, provider, and model before sending.' }
        }
        $observedAt = [DateTimeOffset]::MinValue
        $evidenceMatchesService = $null -ne $OpenCodePermissionEvidence -and
            [string]$OpenCodePermissionEvidence.Source -ceq 'live-api' -and
            ([string]$OpenCodePermissionEvidence.BaseUrl).TrimEnd('/') -ceq $baseUrl.TrimEnd('/') -and
            [string]$OpenCodePermissionEvidence.AgentId -ceq [string]$Config.agentId -and
            [string]$OpenCodePermissionEvidence.ProviderId -ceq $provider -and
            [string]$OpenCodePermissionEvidence.Model -ceq $model -and
            ([string]$OpenCodePermissionEvidence.ProviderEndpointUrl).TrimEnd('/') -ceq $ObservedProviderEndpointUrl.TrimEnd('/') -and
            [DateTimeOffset]::TryParse([string]$OpenCodePermissionEvidence.ObservedAtUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$observedAt)
        $age = [DateTimeOffset]::UtcNow - $observedAt
        $liveVerified = $evidenceMatchesService -and $age.TotalSeconds -ge 0 -and $age.TotalSeconds -le 30
        $profileArgs = @{}
        if ($Config.ContainsKey('capabilityToggles')) { $profileArgs.CapabilityToggles = $Config.capabilityToggles }
        $generatedConfig = New-SlopControlledConfig -Profile ([string]$Config.capabilityProfile) `
            -AgentId ([string]$Config.agentId) -Model $model @profileArgs
        $evidence = $OpenCodePermissionEvidence
        $profileResult = Test-SlopEffectivePermissions -GeneratedConfig $generatedConfig `
            -LiveRules $(if ($liveVerified) { @($evidence.LiveRules) } else { @() }) `
            -SavedGrants $(if ($liveVerified) { @($evidence.SavedGrants) } else { @() }) `
            -EffectivePolicies $(if ($liveVerified) { @($evidence.EffectivePolicies) } else { @() }) `
            -LiveVerified $liveVerified
        $bridge = Join-Path $ScriptRootPath 'Slop.OpenCode.ps1'
        $lifecycle = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
        $auth = @{}
        if ($profileResult.Verified) {
            $auth = New-SlopOpenCodeAuthHeader -ServiceConfigPath $Config.serviceConfigPath -BaseUrl $baseUrl
        }
        return @{
            Ok=$true; Kind=$kind; StatusText=$(if ($profileResult.Verified) { 'Using OpenCode' } else { 'OpenCode permissions need verification' })
            ReadyToSend=[bool]$profileResult.Verified
            AdapterPath=(Join-Path $ScriptRootPath 'Slop.Adapter.OpenCode.ps1')
            AdapterArgs=@{
                BaseUrl=$baseUrl; PromptBody=(New-SlopPromptBody -Text $UserText `
                    -Instructions ([string]$Config.instructions) `
                    -Persona $PersonaText `
                    -Name ([string]$Config.name) `
                    -OwnerName ([string]$Config.ownerName))
                LifecyclePath=$lifecycle; BridgePath=$bridge
                Auth=$auth
                EventTypes=@(Get-SlopOpenCodeEventTypes); TimeoutSeconds=300
                SessionId=$Config.openCodeSessionId; AgentId=[string]$Config.agentId
                ProviderId=$provider; Model=$model
                PermissionProfileVerified=[bool]$profileResult.Verified
            }
            Badge=(Get-SlopRouteBadge -Kind $kind -Provider $provider -Model $model)
            RouteKind=$kind
            RequiresDisclosure=[bool]$catalog[$kind].TermsRequired
            PermissionProfile=[string]$Config.capabilityProfile
            PermissionProfileVerified=[bool]$profileResult.Verified
            PermissionCheck=$profileResult
        }
    }

    $lifecyclePath = Join-Path $ScriptRootPath 'Slop.Lifecycle.ps1'
    $body = New-SlopChatRequestBody -SystemPrompt $PersonaText -UserText $UserText -History $History -Attachments $Attachments -DisableThinking
    # The bundled runtime lives under the app root the caller passed in, not
    # a hard-coded install directory. This is the same root used when Sloppy is
    # installed under LOCALAPPDATA and when it is launched straight from a clone.
    $paths = Get-SlopRuntimePaths -InstallRoot $RepoRootPath -ModelFile ([string]$Config.localModelFile) -MmprojFile ([string]$Config.localMmprojFile)
    $pre = Test-SlopLocalModelPaths -Paths $paths
    if (-not $pre.Ok) { return @{ Ok=$false; Kind=$kind; Reason=$pre.Reason } }
    if ($LocalModelProcess -and -not (Test-SlopOwnedModelProcess -Paths $paths -Process $LocalModelProcess)) {
        return @{ Ok=$false; Kind=$kind; Reason='the existing local brain is not the verified Sloppy-owned process' }
    }
    $contextSize = Resolve-SlopLocalContextSize -ContextSize ([int]$Config.localContextSize)
    $modelName = if (-not [string]::IsNullOrWhiteSpace([string]$Config.localModelName)) { [string]$Config.localModelName } else { Get-SlopBundledModelName }
    return @{
        Ok=$true; Kind='builtin'; StatusText=$(if ($LocalModelProcess) { 'Ready' } else { 'Waking up' })
        ReadyToSend=[bool]$LocalModelProcess
        Process=$LocalModelProcess; LocalModelPaths=$paths; LocalModelContextSize=$contextSize
        NeedsLocalModelStart=(-not [bool]$LocalModelProcess)
        AdapterPath=(Join-Path $ScriptRootPath 'Slop.Adapter.OpenAi.ps1')
        AdapterArgs=@{
            BaseUrl=("http://127.0.0.1:$($paths.Port)")
            RequestBody=$body; LifecyclePath=$lifecyclePath; TimeoutSeconds=300
        }
        Badge=(Get-SlopRouteBadge -Kind 'local-bundled' -Provider 'bundled' -Model $modelName)
        RouteKind='local-bundled'; RequiresDisclosure=$false; PermissionProfile='companion'
    }
}
