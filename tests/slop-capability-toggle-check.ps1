#requires -Version 7.6
Describe 'Slop capability toggles' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.CapabilityToggles.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
    }

    It 'stores six named toggles, all off by default' {
        $defaults = Get-SlopDefaultCapabilityToggles
        @($defaults.Keys).Count | Should -Be 6
        foreach ($value in $defaults.Values) { $value | Should -BeFalse }
    }

    It 'rejects unknown toggles and non-boolean values' {
        (Test-SlopCapabilityToggles -Toggles @{ bogus = $true }).Ok | Should -BeFalse
        (Test-SlopCapabilityToggles -Toggles @{ workspaceFiles = 'yes' }).Ok | Should -BeFalse
    }

    It 'resolves companion, workspace, and power profiles from toggles' {
        Get-SlopCapabilityProfile -Toggles (Get-SlopDefaultCapabilityToggles) | Should -Be 'companion'
        $t = Get-SlopDefaultCapabilityToggles
        $t.workspaceFiles = $true
        Get-SlopCapabilityProfile -Toggles $t | Should -Be 'workspace'
        $t.shellCommands = $true
        Get-SlopCapabilityProfile -Toggles $t | Should -Be 'power'
    }

    It 'never removes hard denies from generated permissions' {
        $t = Get-SlopDefaultCapabilityToggles
        $t.externalFolders = $true
        $t.webAccess = $true
        $profile = Get-SlopCapabilityProfile -Toggles $t
        $cfg = New-SlopControlledConfig -Profile $profile -AgentId sloppy -Model beam-free -CapabilityToggles $t
        $json = $cfg | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Match 'service\.json'
        $json | Should -Match '169\.254\.169\.254'
        $json | Should -Match 'file://\*'
    }

    It 'maps the six toggle keys to fixed OpenCode permission actions' {
        $map = Get-SlopCapabilityToggleMap
        $map.workspaceFiles | Should -Be 'read'
        $map.webAccess | Should -Be 'webfetch'
        $map.shellCommands | Should -Be 'shell'
        $map.skillsPlugins | Should -Be 'tool.use'
        $map.subagentsTasks | Should -Be 'subagent'
        $map.externalFolders | Should -Be 'external_directory'
    }

    It 'adds narrow allows only and never a wildcard rule' {
        $t = Get-SlopDefaultCapabilityToggles
        $t.workspaceFiles = $true
        $t.externalFolders = $true
        $cfg = New-SlopControlledConfig -Profile workspace -AgentId sloppy -Model beam-free -CapabilityToggles $t
        $allows = @($cfg.permissions | Where-Object { $_.effect -eq 'allow' })
        @($allows | Where-Object { $_.resource -eq '*' }).Count | Should -Be 0
        @($allows | Where-Object { $_.resource -like 'C:\Users\*' }).Count | Should -Be 0
    }

    It 'requires disclosure copy for web access and shell commands' {
        $disclosure = Get-SlopCapabilityDisclosure
        @($disclosure.Keys).Count | Should -Be 6
        $disclosure.webAccess | Should -Match 'beyond this PC'
        $disclosure.shellCommands | Should -Match 'change files'
    }
}
