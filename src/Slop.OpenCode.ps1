# S.L.O.P. OpenCode bridge helpers: pure config, JSON, event and SSE logic. No WPF, no HTTP.
$ErrorActionPreference = 'Stop'

$script:SlopOpenCodeEventTypes = @(
    'session.text.delta',
    'session.step.first-token',
    'session.execution.succeeded',
    'session.execution.failed',
    'session.execution.interrupted',
    'session.idle',
    'permission.asked',
    'permission.replied'
)

function Get-SlopOpenCodeEventTypes { return @($script:SlopOpenCodeEventTypes) }

function Test-SlopOpenCodeConfig {
    param(
        [Parameter(Mandatory)][string]$RepoConfigPath,
        [string]$GlobalConfigPath
    )
    # The global config is now the permission model by design, so it is not
    # treated as an override. The tripwire only guards Sloppy's own invariants.
    $errors = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path $RepoConfigPath)) { $errors.Add('repo config missing'); return @{ Ok = $false; Errors = $errors.ToArray() } }
    try { $repo = Get-Content $RepoConfigPath -Raw | ConvertFrom-Json } catch { $errors.Add('repo config invalid JSON'); return @{ Ok = $false; Errors = $errors.ToArray() } }

    $agent = $repo.agents.sloppy
    if (-not $agent) { $errors.Add('sloppy agent missing') }
    else {
        if ($agent.mode -ne 'primary') { $errors.Add('agent is not primary') }
        $system = [string]$agent.system
        if (-not $system -or
            $system -match '\{file:.*personality\.md\}' -or
            $system -notmatch 'Sloppy' -or
            $system -notmatch 'companion persona supplied in the request') {
            $errors.Add('companion persona must be supplied in the request, not from a machine-level personality file')
        }

        $rules = @($agent.permissions)
        if (@($rules | Where-Object {
            $_.action -eq '*' -and $_.resource -eq '*' -and $_.effect -eq 'deny'
        }).Count -gt 0) { $errors.Add('blanket deny rule would strip inherited permissions') }
        if (@($rules | Where-Object { $_.effect -eq 'ask' }).Count -gt 0) { $errors.Add('agent-level ask rules would change the inherited permission model') }

        # One allow only: harmless .env.example files. The agent contributes no
        # external_directory grant; the local service owns workspace scope.
        $allows = @($rules | Where-Object { $_.effect -eq 'allow' })
        $hasEnvExample = @($allows | Where-Object { $_.action -eq 'read' -and $_.resource -ceq '*.env.example' }).Count -eq 1
        $hasExternalGrant = @($allows | Where-Object { $_.action -eq 'external_directory' }).Count -gt 0
        if ($allows.Count -ne 1 -or -not $hasEnvExample -or $hasExternalGrant) {
            $errors.Add('only *.env.example may be allowed; external_directory grants are forbidden')
        }

        foreach ($p in @(
            '~/.config/opencode/service.json', '~/.ssh/*', '*.env', '*.env.*', '~/.aws/*', '~/.config/gcloud/*'
        )) {
            if (@($rules | Where-Object { $_.action -eq 'read' -and $_.resource -ceq $p -and $_.effect -eq 'deny' }).Count -eq 0) {
                $errors.Add("agent private read deny missing: $p")
            }
        }

        foreach ($p in @(
            '*127.0.0.1*', '*localhost*', '*169.254.169.254*', '*file://*',
            '*[::1]*', '*://127.*', '*metadata.google.internal*',
            '*100.100.100.200*', '*0.0.0.0*'
        )) {
            if (@($rules | Where-Object { $_.action -eq 'webfetch' -and $_.resource -ceq $p -and $_.effect -eq 'deny' }).Count -eq 0) {
                $errors.Add("agent private webfetch deny missing: $p")
            }
        }
    }

    # Top-level repo policies are intentionally muted: OpenCode applied them to
    # every agent in the repo, including the development session, and a deny
    # policy has no approval path. Fail closed if someone re-enables them.
    if ($null -ne $repo.policies -and @($repo.policies).Count -gt 0) { $errors.Add('repo-wide policies are active but must remain muted') }

    # The global config owns providers/permissions. It was previously accepted
    # as a parameter but never inspected. Fail closed on a missing/broken file
    # or an opt-in to outbound telemetry/auto-update. Remote MCP hosts are left
    # alone: those are intentional in this workspace.
    if ([string]::IsNullOrWhiteSpace($GlobalConfigPath) -or -not (Test-Path $GlobalConfigPath)) {
        $errors.Add('global config missing')
    } else {
        try { $globalCfg = Get-Content $GlobalConfigPath -Raw | ConvertFrom-Json }
        catch { $errors.Add('global config invalid JSON') }
        if ($null -ne $globalCfg) {
            foreach ($flag in @('telemetry','autoupdate','autoUpdate')) {
                $v = $globalCfg.PSObject.Properties[$flag]
                if ($null -ne $v -and $v.Value -is [bool] -and $v.Value) { $errors.Add("global config enables $flag") }
            }
        }
    }
    return @{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function New-SlopPromptBody {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$MaxLength = 8000,
        [string]$Instructions = '',
        [string]$Persona = '',
        [string]$Name = '',
        [string]$OwnerName = ''
    )
    $text = [string]$Text
    $prefixParts = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Name) -or -not [string]::IsNullOrWhiteSpace($OwnerName)) {
        $who = [Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($Name)) { $who.Add("Your name is $($Name.Trim()).") | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($OwnerName)) { $who.Add("The owner's name is $($OwnerName.Trim()).") | Out-Null }
        if ($who.Count -gt 0) { $prefixParts.Add(($who -join ' ')) | Out-Null }
    }
    if (-not [string]::IsNullOrWhiteSpace($Persona)) {
        $prefixParts.Add("Personality/style: $($Persona.Trim())") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($Instructions)) {
        $prefixParts.Add("Custom instructions: $($Instructions.Trim())") | Out-Null
    }
    if ($prefixParts.Count -gt 0) {
        $prefix = "[Sloppy local context]`n" + ($prefixParts -join "`n") + "`n[/Sloppy local context]`n`n"
        $text = $prefix + $text
    }
    if ($text.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    return @{ text = $text } | ConvertTo-Json -Depth 4 -Compress
}

function New-SlopPermissionReply {
    param([Parameter(Mandatory)][ValidateSet('once','reject')][string]$Decision)
    return @{ decision = $Decision } | ConvertTo-Json -Depth 4 -Compress
}

function Test-SlopOpenCodeServiceUrl {
    param([Parameter(Mandatory)][string]$BaseUrl)
    $uri = $null
    if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'http' -or -not $uri.IsLoopback) { return $false }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) { return $false }
    return $true
}

function New-SlopOpenCodeAuthHeader {
    param(
        # Optional path to the OpenCode service credential file. Credentials are
        # never copied into Sloppy's own config; this only reads the password.
        [string]$ServiceConfigPath,
        [string]$BaseUrl = $(if ($env:OPENCODE_BASE_URL) { $env:OPENCODE_BASE_URL } else { 'http://127.0.0.1:28894' })
    )
    if (-not (Test-SlopOpenCodeServiceUrl -BaseUrl $BaseUrl)) {
        throw 'OpenCode service URL must be loopback http; refusing to attach its credential'
    }
    $password = $env:OPENCODE_PASSWORD
    if ([string]::IsNullOrEmpty($password) -and -not [string]::IsNullOrWhiteSpace($ServiceConfigPath) -and
        (Test-Path -LiteralPath $ServiceConfigPath)) {
        try {
            $serviceConfig = Get-Content -LiteralPath $ServiceConfigPath -Raw | ConvertFrom-Json
            if ($serviceConfig.password) { $password = [string]$serviceConfig.password }
        }
        catch { # malformed service config falls through to the clear error below
        }
    }
    if ([string]::IsNullOrEmpty($password)) { throw 'OPENCODE_PASSWORD is not set' }
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("opencode:$password"))
    return @{ Authorization = "Basic $token" }
}

function Test-SlopOpenCodeEvent {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$SessionID,
        [Parameter(Mandatory)][string[]]$AllowedTypes
    )
    $reject = @{ Accepted = $false; Type = $null; Text = $null; RequestID = $null; Action = $null; Resources = @() }
    try { $evt = $Json | ConvertFrom-Json } catch { return $reject }
    if (-not $evt.type -or $evt.type -notin $AllowedTypes) { return $reject }
    if (-not $evt.data -or -not $evt.data.sessionID -or $evt.data.sessionID -cne $SessionID) { return $reject }
    $result = @{ Accepted = $true; Type = $evt.type; Text = $null; RequestID = $null; Action = $null; Resources = @() }
    switch ($evt.type) {
        'session.text.delta' {
            if ($null -eq $evt.data.delta) { return $reject }
            $result.Text = [string]$evt.data.delta
        }
        'permission.asked' {
            if (-not $evt.data.id -or -not $evt.data.action) { return $reject }
            $result.RequestID = [string]$evt.data.id
            $result.Action = [string]$evt.data.action
            if ($evt.data.resources) { $result.Resources = @($evt.data.resources | ForEach-Object { [string]$_ }) }
        }
    }
    return $result
}

function Read-SlopOpenCodeSse {
    param(
        [Parameter(Mandatory)][IO.TextReader]$Reader,
        [Parameter(Mandatory)][Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [Parameter(Mandatory)][string]$SessionID,
        [Parameter(Mandatory)][string[]]$AllowedTypes,
        [Parameter(Mandatory)][Threading.CancellationTokenSource]$Cts
    )
    $events = 0; $malformed = 0
    while (-not $Cts.IsCancellationRequested) {
        # Token-aware read inherited from Slop.Lifecycle.ps1 — a stalled server cannot hold the UI.
        $line = $Reader.ReadLineAsync($Cts.Token).GetAwaiter().GetResult()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:')) { $malformed++; continue }
        $payload = $line.Substring(5).Trim()
        if (-not $payload) { continue }
        $ev = Test-SlopOpenCodeEvent -Json $payload -SessionID $SessionID -AllowedTypes $AllowedTypes
        if (-not $ev.Accepted) { continue }
        $events++
        $terminal = $false
        switch ($ev.Type) {
            'session.text.delta'   { if ($ev.Text) { $Queue.Enqueue("__TOK__$($ev.Text)") } }
            'permission.asked'     { $Queue.Enqueue("__OCASK__$($ev.RequestID)|$($ev.Action)|$(($ev.Resources -join ',') -replace '[\|\r\n]',' ')") }
            'permission.replied'   { $Queue.Enqueue('__OCREPLIED__') }
            # OpenCode v2.3.2 emits execution terminals but no session.idle after a
            # rejected permission. Finalize on the terminal so Send is re-enabled
            # instead of waiting for the whole request timeout. __DONE__ is queued
            # after the signal so the overlay is rendered before finalize.
            'session.execution.succeeded'    { $Queue.Enqueue('__OCSUCCESS__');   $Queue.Enqueue('__DONE__'); $terminal = $true }
            'session.execution.failed'       { $Queue.Enqueue('__ERR__OpenCode execution failed'); $Queue.Enqueue('__DONE__'); $terminal = $true }
            'session.execution.interrupted'  { $Queue.Enqueue('__ERR__Cancelled'); $Queue.Enqueue('__DONE__'); $terminal = $true }
            'session.idle'                   { $Queue.Enqueue('__DONE__'); $terminal = $true }
        }
        if ($terminal) { break }
    }
    return @{ Events = $events; Malformed = $malformed; Cancelled = $Cts.IsCancellationRequested }
}
