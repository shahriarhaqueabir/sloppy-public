# Sloppy Tier 2 model catalog filter. Pure headless helpers; no WPF dependency.
# The shell dot-sources Slop.Config.ps1 first so Test-SlopLoopbackHttpUrl exists.
# Only Id and Name leave this boundary; raw payload, headers, exception text,
# service identifiers and credentials are never returned or logged here.

function Get-SlopFreeChatModels {
    param([Parameter(Mandatory)][AllowNull()]$CatalogData)

    $items = @()
    if ($null -ne $CatalogData -and $CatalogData.PSObject.Properties['data']) {
        $items = @($CatalogData.data)
    } elseif ($null -ne $CatalogData -and $CatalogData -is [System.Collections.IEnumerable] -and $CatalogData -isnot [string]) {
        $items = @($CatalogData)
    }

    $byId = [ordered]@{}
    $preferred = @{}
    foreach ($item in $items) {
        if ([string]$item.type -cne 'chat') { continue }
        if ($null -ne $item.enabled -and [bool]$item.enabled -eq $false) { continue }
        if ([string]$item.status -cne 'active') { continue }

        $costEntries = @()
        if ($null -ne $item.cost) { $costEntries = @($item.cost) }
        if ($costEntries.Count -eq 0) { continue }
        $free = $true
        foreach ($entry in $costEntries) {
            $inputCost = 0.0
            $outputCost = 0.0
            if ($null -ne $entry) {
                [void][double]::TryParse([string]$entry.input, [ref]$inputCost)
                [void][double]::TryParse([string]$entry.output, [ref]$outputCost)
            }
            if ($inputCost -ne 0 -or $outputCost -ne 0) { $free = $false; break }
        }
        if (-not $free) { continue }

        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
        $isPreferred = ([string]$item.providerID -ceq 'opencode')

        if ($byId.Contains($id)) {
            if ($isPreferred -and -not [bool]$preferred[$id]) {
                $byId[$id] = @{ Id = $id; Name = $name }
                $preferred[$id] = $true
            }
            continue
        }
        $byId[$id] = @{ Id = $id; Name = $name }
        $preferred[$id] = $isPreferred
    }

    $all = @($byId.Values)
    $pinned = @($all | Where-Object { $_.Id -ceq 'big-pickle' })
    $rest = @($all | Where-Object { $_.Id -cne 'big-pickle' } | Sort-Object -Property Name -CaseSensitive)
    return @($pinned + $rest)
}

function Get-SlopModelCatalogResult {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [hashtable]$Headers
    )

    if (-not (Test-SlopLoopbackHttpUrl -Url $BaseUrl)) {
        return @{ Ok = $false; Models = @(); Error = 'OpenCode service URL must be loopback.' }
    }
    try {
        $uri = $BaseUrl.Trim().TrimEnd('/') + '/api/model'
        $response = Invoke-WebRequest -Uri $uri -Headers $Headers -UseBasicParsing -TimeoutSec 8
        if ([int]$response.StatusCode -ne 200) {
            return @{ Ok = $false; Models = @(); Error = 'OpenCode model catalog could not be read.' }
        }
        $payload = $response.Content | ConvertFrom-Json
        $models = @(Get-SlopFreeChatModels -CatalogData $payload)
        return @{ Ok = $true; Models = $models; Error = '' }
    } catch {
        return @{ Ok = $false; Models = @(); Error = 'OpenCode model catalog could not be read.' }
    }
}

function Get-SlopModelCatalogStatusText {
    param([Parameter(Mandatory)][hashtable]$Result)
    if (-not [bool]$Result.Ok) { return [string]$Result.Error }
    $count = @($Result.Models).Count
    if ($count -eq 0) { return 'No free chat models returned.' }
    return "$count free chat models available."
}
