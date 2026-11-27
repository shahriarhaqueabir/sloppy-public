# Controlled OpenCode config generation and fail-closed verification. Headless.
$ErrorActionPreference = 'Stop'

# Capability resolution is a pure module. Dot-source it so New-SlopControlledConfig
# can resolve a profile from toggles even when the shell has not loaded it.
$capabilityModule = Join-Path $PSScriptRoot 'Slop.CapabilityToggles.ps1'
if (Test-Path -LiteralPath $capabilityModule) { . $capabilityModule }

function Get-SlopProfileApprovalModes { return @('once','reject') }

function New-SlopPermissionProfile {
    param(
        [Parameter(Mandatory)][ValidateSet('companion','workspace','power')][string]$Name,
        [string[]]$WorkspaceFolders = @()
    )
    $denyAll = @{ action='*'; resource='*'; effect='deny' }
    $secretDenies = @(
        @{ action='read';  resource='**/service.json'; effect='deny' },
        @{ action='read';  resource='**/.env*';       effect='deny' },
        @{ action='read';  resource='**/.ssh/*';      effect='deny' },
        @{ action='read';  resource='**/.aws/*';      effect='deny' },
        @{ action='read';  resource='**/.config/gcloud/*'; effect='deny' },
        @{ action='webfetch'; resource='file://*';    effect='deny' },
        @{ action='webfetch'; resource='http://127.0.0.1/*'; effect='deny' },
        @{ action='webfetch'; resource='http://localhost/*'; effect='deny' },
        @{ action='webfetch'; resource='http://169.254.169.254/*'; effect='deny' }  # cloud metadata
    )
    switch ($Name) {
        'companion' {
            return @{ Permissions=@($denyAll) + $secretDenies; Policies=@(
                @{ action='tool.use'; resource='shell:*'; effect='deny' }
            ) }
        }
        'workspace' {
            $allows = @()
            foreach ($folder in $WorkspaceFolders) {
                $allows += @{ action='external_directory'; resource=$folder; effect='allow' }
                $allows += @{ action='read'; resource=$folder; effect='allow' }
                $allows += @{ action='glob'; resource=$folder; effect='allow' }
            }
            return @{ Permissions=@($denyAll) + $secretDenies + $allows; Policies=@(
                @{ action='tool.use'; resource='shell:*'; effect='deny' }
            ) }
        }
        'power' {
            return @{ Permissions=@($denyAll) + $secretDenies + @(
                @{ action='shell'; resource='git status *'; effect='allow' }
            ); Policies=@(
                @{ action='tool.use'; resource='shell:sudo *'; effect='deny' },
                @{ action='tool.use'; resource='shell:rm -rf *'; effect='deny' }
            ) }
        }
    }
}

function New-SlopControlledConfig {
    param(
        [string]$Profile,
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$Model,
        [string[]]$WorkspaceFolders = @(),
        [hashtable]$CapabilityToggles = $null
    )
    $toggleSet = $CapabilityToggles
    $effectiveToggles = if ($null -ne $toggleSet) { $toggleSet } else { Get-SlopDefaultCapabilityToggles }
    $profileName = if ([string]::IsNullOrWhiteSpace([string]$Profile)) {
        Get-SlopCapabilityProfile -Toggles $effectiveToggles
    } else {
        [string]$Profile
    }
    $profileRules = New-SlopPermissionProfile -Name $profileName -WorkspaceFolders $WorkspaceFolders

    # Deny-all stays first. Capability allows punch only narrow holes; the
    # secret hard denies are appended last so they always win under findLast
    # (no web toggle can re-allow file://, loopback or cloud metadata).
    $denyAll = @{ action='*'; resource='*'; effect='deny' }
    $secretDenies = @($profileRules.Permissions | Where-Object {
        $_.effect -eq 'deny' -and $_.resource -ne '*'
    })
    $allows = @()
    if ($null -eq $toggleSet) {
        # Legacy callers pass no toggles: keep the profile's existing allows.
        $allows = @($profileRules.Permissions | Where-Object { $_.effect -eq 'allow' })
    } else {
        $map = Get-SlopCapabilityToggleMap
        foreach ($key in $map.Keys) {
            if (-not $effectiveToggles.ContainsKey($key)) { continue }
            if ($effectiveToggles[$key] -isnot [bool] -or $effectiveToggles[$key] -ne $true) { continue }
            $action = $map[$key]
            switch ($key) {
                'workspaceFiles'  { $allows += @{ action=$action; resource='./**'; effect='allow' } }
                'webAccess'       {
                    $allows += @{ action=$action; resource='https://*'; effect='allow' }
                    $allows += @{ action=$action; resource='http://*';  effect='allow' }
                }
                'shellCommands'   { $allows += @{ action=$action; resource='git status *'; effect='allow' } }
                'skillsPlugins'   { $allows += @{ action=$action; resource='skill:*'; effect='allow' } }
                'subagentsTasks'  { $allows += @{ action=$action; resource='task:*'; effect='allow' } }
                'externalFolders' {
                    foreach ($folder in @($WorkspaceFolders)) {
                        $allows += @{ action=$action; resource=$folder; effect='allow' }
                    }
                }
            }
        }
    }
    $permissions = @($denyAll) + @($allows) + @($secretDenies)
    return @{
        '$schema'   = 'https://opencode.ai/config.json'
        model       = $Model
        permissions = $permissions
        policies    = @($profileRules.Policies)
        agents      = @{
            $AgentId = @{
                description = 'Sloppy companion agent. Capabilities come from the selected profile.'
                system      = 'You are a warm desktop companion. Be concise and honest about what you can do.'
                permissions = $permissions
            }
        }
    }
}

function Test-SlopEffectivePermissions {
    param(
        [Parameter(Mandatory)][hashtable]$GeneratedConfig,
        [object[]]$LiveRules = @(),
        [object[]]$SavedGrants = @(),
        [object[]]$EffectivePolicies = @(),
        [bool]$LiveVerified = $false
    )
    $reasons = [Collections.Generic.List[string]]::new()
    $denies = @($GeneratedConfig.policies | Where-Object { $_.action -eq 'tool.use' -and $_.effect -eq 'deny' })
    if ($denies.Count -eq 0) { $reasons.Add('generated hard-deny policies are missing') }
    if (-not $LiveVerified) { $reasons.Add('active OpenCode configuration has not been verified') }

    foreach ($rule in @($LiveRules) + @($SavedGrants)) {
        if ($rule.effect -eq 'allow' -and ($rule.action -eq '*' -or $rule.resource -eq '*')) {
            $reasons.Add('unbounded allow survives in active rules')
        }
        if ($rule.action -eq 'external_directory' -and $rule.resource -eq '*' -and $rule.effect -eq 'allow') {
            $reasons.Add('broad external_directory allow survives')
        }
        if ($rule.action -eq 'edit' -and $rule.resource -eq '*' -and $rule.effect -eq 'allow') {
            $reasons.Add('saved grant allows edit everywhere')
        }
    }
    if ($LiveVerified) {
        foreach ($expected in @($GeneratedConfig.permissions)) {
            if (@($LiveRules | Where-Object {
                $_.action -ceq $expected.action -and $_.resource -ceq $expected.resource -and $_.effect -ceq $expected.effect
            }).Count -eq 0) {
                $reasons.Add("active agent is missing permission rule: $($expected.action) $($expected.resource) $($expected.effect)")
            }
        }
        if (@($SavedGrants).Count -gt 0) {
            $reasons.Add('saved Allow always grants are present for this project')
        }
        if (@($EffectivePolicies | Where-Object { $_.action -eq 'tool.use' -and $_.effect -eq 'deny' }).Count -eq 0) {
            $reasons.Add('active service has no effective hard-deny policy')
        }
        foreach ($expected in $denies) {
            if (@($EffectivePolicies | Where-Object {
                $_.action -eq $expected.action -and $_.resource -ceq $expected.resource -and $_.effect -eq 'deny'
            }).Count -eq 0) {
                $reasons.Add("active service is missing hard-deny policy: $($expected.resource)")
            }
        }
    }
    return @{ Ok=($reasons.Count -eq 0); Verified=($LiveVerified -and $reasons.Count -eq 0); Reasons=$reasons.ToArray() }
}
