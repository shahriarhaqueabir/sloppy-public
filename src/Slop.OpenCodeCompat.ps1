# Pinned OpenCode version and the exact API surface the Tier 2 bridge depends on. Headless.
$ErrorActionPreference = 'Stop'

function Get-SlopOpenCodeCompatContract {
    return @{
        PinnedVersion  = '2.4.2'
        RequiredRoutes = @(
            @{ Method='GET';    Path='/api/config' }
            @{ Method='GET';    Path='/api/agent' }
            @{ Method='GET';    Path='/api/model' }
            @{ Method='GET';    Path='/api/provider' }
            @{ Method='POST';   Path='/api/session' }
            @{ Method='POST';   Path='/api/session/{id}/agent' }
            @{ Method='POST';   Path='/api/session/{id}/model' }
            @{ Method='POST';   Path='/api/session/{id}/prompt' }
            @{ Method='POST';   Path='/api/session/{id}/interrupt' }
            @{ Method='POST';   Path='/api/session/{id}/permission/{permissionID}/reply' }
            @{ Method='DELETE'; Path='/api/session/{id}' }
            @{ Method='GET';    Path='/api/event?types=...' }
            @{ Method='GET';    Path='/api/permission/saved' }
        )
    }
}

function Test-SlopOpenCodeCompatContract {
    param(
        [Parameter(Mandatory)][hashtable]$Observed,
        [hashtable]$Contract = (Get-SlopOpenCodeCompatContract)
    )
    $reasons = [Collections.Generic.List[string]]::new()
    if ([string]$Observed.version -ne [string]$Contract.PinnedVersion) {
        $reasons.Add("OpenCode version $($Observed.version) is not the supported $($Contract.PinnedVersion)")
    }
    $seen = @($Observed.routes | ForEach-Object { if ($_ -is [hashtable]) { $_.Method + ' ' + $_.Path } else { [string]$_ } })
    foreach ($route in $Contract.RequiredRoutes) {
        $needle = $route.Method + ' ' + $route.Path
        if ($needle -notin $seen) { $reasons.Add("missing route: $needle") }
    }
    return @{ Ok=($reasons.Count -eq 0); Reasons=$reasons.ToArray() }
}
