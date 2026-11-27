# OpenCode compatibility floor and the exact API surface the Tier 2 bridge depends on. Headless.
# Versions at or above MinimumVersion are supported while the route surface matches; VerifiedVersion
# records the newest release actually exercised, not an exact pin that every update would invalidate.
$ErrorActionPreference = 'Stop'

function Get-SlopOpenCodeCompatContract {
    return @{
        MinimumVersion  = '2.3.2'
        VerifiedVersion = '2.4.2'
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

function Get-SlopVersionParts {
    param([Parameter(Mandatory)][string]$Version)
    $parts = ($Version -replace '^v', '').Split('.')
    if ($parts.Count -lt 2 -or @($parts | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) {
        return $null
    }
    return @($parts | ForEach-Object { [int]$_ })
}

function Test-SlopVersionAtLeast {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Minimum
    )
    $actual = Get-SlopVersionParts -Version $Version
    $floor = Get-SlopVersionParts -Version $Minimum
    if ($null -eq $actual -or $null -eq $floor) { return $false }
    $length = [Math]::Max($actual.Count, $floor.Count)
    for ($i = 0; $i -lt $length; $i++) {
        $a = if ($i -lt $actual.Count) { $actual[$i] } else { 0 }
        $f = if ($i -lt $floor.Count) { $floor[$i] } else { 0 }
        if ($a -gt $f) { return $true }
        if ($a -lt $f) { return $false }
    }
    return $true
}

function Test-SlopOpenCodeCompatContract {
    param(
        [Parameter(Mandatory)][hashtable]$Observed,
        [hashtable]$Contract = (Get-SlopOpenCodeCompatContract)
    )
    $reasons = [Collections.Generic.List[string]]::new()
    if (-not (Test-SlopVersionAtLeast -Version ([string]$Observed.version) -Minimum $Contract.MinimumVersion)) {
        $reasons.Add("OpenCode version $($Observed.version) is below the supported minimum $($Contract.MinimumVersion)")
    }
    $seen = @($Observed.routes | ForEach-Object { if ($_ -is [hashtable]) { $_.Method + ' ' + $_.Path } else { [string]$_ } })
    foreach ($route in $Contract.RequiredRoutes) {
        $needle = $route.Method + ' ' + $route.Path
        if ($needle -notin $seen) { $reasons.Add("missing route: $needle") }
    }
    return @{ Ok=($reasons.Count -eq 0); Reasons=$reasons.ToArray() }
}
