#requires -Version 7.6
Describe 'Slop.OpenCodeProfile' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
    }
    It 'generates a deny-first companion profile' {
        $cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $cfg.permissions[0].effect | Should -Be 'deny'
        $cfg.agents.sloppy.permissions | Should -Not -BeNullOrEmpty
    }
    It 'includes hard-deny policies' {
        $cfg = New-SlopControlledConfig -Profile 'power' -AgentId 'sloppy' -Model 'beam-free'
        # @(...) is required: a lone hashtable's .Count is its key count, not 1.
        @($cfg.policies | Where-Object { $_.action -eq 'tool.use' -and $_.effect -eq 'deny' }).Count |
            Should -BeGreaterThan 0
        $json = $cfg | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Match '169\.254\.169\.254'
        $json | Should -Match 'service\.json'
    }
    It 'fails closed when a broad allow survives in live rules' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $live = @(@{ action='*'; resource='*'; effect='allow' })
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules $live -SavedGrants @() -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'unbounded allow'
    }
    It 'fails closed on a saved edit-all grant' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $grants = @(@{ action='edit'; resource='*'; effect='allow' })
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules @() -SavedGrants $grants -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'saved grant'
    }
    It 'fails closed when hard-deny policies are missing' {
        $generated = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        $generated.policies = @()
        $result = Test-SlopEffectivePermissions -GeneratedConfig $generated -LiveRules @() -SavedGrants @() -EffectivePolicies @()
        $result.Ok | Should -BeFalse
        $result.Reasons -join ' ' | Should -Match 'hard-deny'
    }
    It 'gives Workspace only the chosen read-only folders' {
        $cfg = New-SlopControlledConfig -Profile 'workspace' -AgentId 'sloppy' -Model 'beam-free' -WorkspaceFolders @('D:/notes/*')
        @($cfg.permissions | Where-Object { $_.action -eq 'external_directory' -and $_.resource -eq 'D:/notes/*' }).Count |
            Should -Be 1
        @($cfg.permissions | Where-Object { $_.action -eq 'shell' -and $_.effect -eq 'allow' }).Count |
            Should -Be 0
    }
    It 'never proposes an Allow always grant' {
        (Get-SlopProfileApprovalModes) -join ',' | Should -Be 'once,reject'
    }
    It 'generates capability-specific allows without broad grants' {
        $t = @{
            workspaceFiles = $false; webAccess = $false; shellCommands = $false
            skillsPlugins = $false; subagentsTasks = $false; externalFolders = $true
        }
        $cfg = New-SlopControlledConfig -CapabilityToggles $t -AgentId 'sloppy' -Model 'beam-free'
        @($cfg.permissions | Where-Object { $_.action -eq 'external_directory' -and $_.resource -eq '*' }).Count |
            Should -Be 0
        $json = $cfg | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Match 'service\.json'
        $json | Should -Match '169\.254\.169\.254'
    }
}
