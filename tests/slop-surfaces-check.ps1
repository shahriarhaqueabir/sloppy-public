#requires -Version 7.6
Describe 'Slop.Surfaces' {
    BeforeAll {
        # Get-SlopDeletionScope delegates copy text to the Disclosure module.
        . (Join-Path $PSScriptRoot '../src/Slop.Disclosure.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Surfaces.ps1')
    }
    It 'exposes exactly four destinations' {
        (Get-SlopDestinationMap).Keys | Sort-Object | Should -Be @('Brain','Customize','Privacy','Settings')
    }
    It 'keeps persona text out of permissions' {
        $r = Test-SlopSurfaceSeparation -Destination 'Customize' -Payload @{ personaText='be warm'; permissions=@() }
        $r.Ok | Should -BeTrue
        $r2 = Test-SlopSurfaceSeparation -Destination 'Customize' -Payload @{ personaText='be warm'; permissions=@(@{effect='allow'}) }
        $r2.Ok | Should -BeFalse
    }
    It 'places developer commands only under Settings Advanced' {
        $m = Get-SlopDestinationMap
        $m.Settings.Contains('Advanced / developer') | Should -BeTrue
        $m.Customize -join ',' | Should -Not -Match 'developer'
    }
    It 'maps each deletion action to a distinct scope' {
        $scopes = @('conversation','session','local-data') | ForEach-Object { (Get-SlopDeletionScope -Action $_).Scope }
        ($scopes | Select-Object -Unique).Count | Should -Be 3
    }
    It 'exposes status, editable, and action IDs for all four destinations' {
        $expected = @{
            Settings  = @{ Status='SettingsStatusText';  Editable=@('VoiceEnabledCheck','VoiceLanguageCombo','VoiceMaxSecondsBox'); Actions=@('SettingsSaveButton','AutostartButton','VoiceRepairButton','SettingsBack') }
            Customize = @{ Status='CustomizeStatusText'; Editable=@('CustomizeNameBox','CustomizeColourCombo','CustomizePersonalityCombo','CustomizePersonaBox'); Actions=@('CustomizeSaveButton','CustomizeBack') }
            Brain     = @{ Status='BrainStatusText';     Editable=@('BrainTypeCombo','BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo'); Actions=@('BrainSaveButton','BrainBack') }
            Privacy   = @{ Status='PrivacyStatusText';   Editable=@(); Actions=@('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton','PrivacyBack') }
        }
        foreach ($name in $expected.Keys) {
            $contract = Get-SlopDestinationContract -Name $name
            $contract.Status | Should -Be $expected[$name].Status
            @($contract.Editable) | Should -Be $expected[$name].Editable
            @($contract.Actions) | Should -Be $expected[$name].Actions
        }
    }

    It 'keeps deletion actions out of Settings and inside Privacy' {
        $settings = Get-SlopDestinationContract -Name 'Settings'
        $privacy = Get-SlopDestinationContract -Name 'Privacy'
        foreach ($id in @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton')) {
            $settings.Actions | Should -Not -Contain $id
            $privacy.Actions | Should -Contain $id
        }
        (Get-SlopDestinationMap).Settings -join ',' | Should -Not -Match 'delete'
        (Get-SlopDestinationMap).Privacy -join ',' | Should -Match 'Deletion actions'
    }

    It 'names destinations by tier instead of free or paid' {
        $map = Get-SlopDestinationMap
        $map.Brain | Should -Contain 'Tier'
        $map.Brain | Should -Not -Contain 'Local vs remote'
        ($map.Values -join ' ') | Should -Not -Match '(?i)\bfree\b|\bpaid\b'
    }

    It 'points deletion copy at the in-app data folder' {
        $pattern = [regex]::Escape('data\config.json')
        Get-SlopDeletionScope -Action 'local-data' | ForEach-Object { $_.Scope } |
            Should -Match $pattern
        Get-SlopDeletionCopy -Action 'local-data' | Should -Not -Match 'LOCALAPPDATA'
    }
}
