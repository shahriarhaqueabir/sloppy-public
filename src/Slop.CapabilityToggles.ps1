# Pure capability toggle validation and profile resolution. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopCapabilityToggleMap {
    return @{
        workspaceFiles   = 'read'
        webAccess        = 'webfetch'
        shellCommands    = 'shell'
        skillsPlugins    = 'tool.use'
        subagentsTasks   = 'subagent'
        externalFolders  = 'external_directory'
    }
}

function Get-SlopDefaultCapabilityToggles {
    $result = @{}
    foreach ($key in (Get-SlopCapabilityToggleMap).Keys) { $result[$key] = $false }
    return $result
}

function Test-SlopCapabilityToggles {
    param([Parameter(Mandatory)][hashtable]$Toggles)
    $errors = [System.Collections.Generic.List[string]]::new()
    $valid = Get-SlopCapabilityToggleMap
    foreach ($key in $Toggles.Keys) {
        if (-not $valid.ContainsKey([string]$key)) {
            $errors.Add("unknown capability toggle: $key")
            continue
        }
        if ($Toggles[$key] -isnot [bool]) {
            $errors.Add("capability toggle must be boolean: $key")
        }
    }
    foreach ($key in $valid.Keys) {
        if (-not $Toggles.ContainsKey($key)) {
            $errors.Add("missing capability toggle: $key")
        }
    }
    return [pscustomobject]@{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Get-SlopCapabilityProfile {
    param([Parameter(Mandatory)][hashtable]$Toggles)
    $check = Test-SlopCapabilityToggles -Toggles $Toggles
    if (-not $check.Ok) { return 'companion' }
    if ($Toggles.shellCommands) { return 'power' }
    if ($Toggles.workspaceFiles -or $Toggles.webAccess -or $Toggles.externalFolders) { return 'workspace' }
    return 'companion'
}

function Get-SlopCapabilityDisclosure {
    return @{
        workspaceFiles  = 'Can read files in the active workspace only.'
        webAccess       = 'Can fetch web content; requests can reach beyond this PC.'
        shellCommands   = 'Can run shell commands that may change files on this PC.'
        skillsPlugins   = 'Can load local skills and plugins from the active workspace.'
        subagentsTasks  = 'Can start bounded subagents and tasks for the current request.'
        externalFolders = 'Can read only folders you explicitly grant; no blanket home access.'
    }
}
