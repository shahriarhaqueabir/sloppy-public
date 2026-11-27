#requires -Version 7.6
# Static information-architecture contracts for Sloppy's four destinations.
# No WPF types: these guards run anywhere the CI suite runs.
Describe 'Slop information architecture' {
    BeforeAll {
        $script:ShellSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
        $script:WizardSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        . (Join-Path $PSScriptRoot '../src/Slop.Disclosure.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Surfaces.ps1')
    }

    It 'Settings leads with Companion, Brain, Voice and Startup groups' {
        $settings = [regex]::Match($script:ShellSrc, 'x:Name="SettingsPanel"[\s\S]*?(?=x:Name="CustomizePanel")').Value
        $settings | Should -Match 'Text="Companion"'
        $settings | Should -Match 'Text="Brain"'
        $settings | Should -Match 'Text="Voice"'
        $settings | Should -Match 'Text="Startup behaviour"'
        $settings | Should -Match 'Name, colour and personality are set in Customize\.'
    }

    It 'Settings shows the effective route read-only instead of editing brain fields' {
        $settings = [regex]::Match($script:ShellSrc, 'x:Name="SettingsPanel"[\s\S]*?(?=x:Name="CustomizePanel")').Value
        $settings | Should -Match 'x:Name="SettingsRouteText"'
        $settings | Should -Not -Match 'TextBox x:Name="SettingsRouteText"'
        $settings | Should -Not -Match 'x:Name="SettingsInstructionsBox"'
        $script:ShellSrc | Should -Not -Match 'SettingsInstructionsBox'
        $script:ShellSrc | Should -Not -Match '\$cfg\.instructions\s*=\s*\[string\]\$Settings'
    }

    It 'Settings keeps raw brain values behind a read-only Advanced expander' {
        $settings = [regex]::Match($script:ShellSrc, 'x:Name="SettingsPanel"[\s\S]*?(?=x:Name="CustomizePanel")').Value
        $advanced = [regex]::Match($settings, '<Expander Header="Advanced"[\s\S]*?</Expander>').Value
        $advanced | Should -Not -BeNullOrEmpty
        foreach ($id in @('SettingsModelBox','SettingsBaseUrlBox','SettingsAgentIdBox')) {
            $advanced | Should -Match ('x:Name="' + $id + '"')
            $advanced | Should -Match ('x:Name="' + $id + '"[^>]*IsReadOnly="True"')
        }
        $settings | Should -Match '<Expander Header="Advanced / developer"'
        $settings | Should -Match 'x:Name="AdvancedStack"'
    }

    It 'Settings no longer writes brain values that Brain owns' {
        $save = [regex]::Match($script:ShellSrc, 'function Save-SlopSettings[\s\S]*?function ').Value
        $save | Should -Not -Match '\$cfg\.model\s*='
        $save | Should -Not -Match '\$cfg\.modelName\s*='
        $save | Should -Not -Match '\$cfg\.openCodeBaseUrl\s*='
        $save | Should -Not -Match '\$cfg\.agentId\s*='
        $save | Should -Match '\$cfg\.voiceMaxSeconds\s*=\s*\$seconds'
    }

    It 'Brain leads with a plain tier choice and keeps raw fields in Advanced' {
        $brain = [regex]::Match($script:ShellSrc, 'x:Name="BrainPanel"[\s\S]*?(?=x:Name="PrivacyPanel")').Value
        $brain | Should -Match 'Text="Where answers come from"'
        $brain | Should -Match 'x:Name="BrainTypeCombo"'
        ([regex]::Matches($brain, 'Text="Where answers come from"'))[0].Index |
            Should -BeLessThan ([regex]::Matches($brain, 'x:Name="BrainTypeCombo"'))[0].Index
        $advanced = [regex]::Match($brain, '<Expander Header="Advanced"[\s\S]*?</Expander>').Value
        $advanced | Should -Not -BeNullOrEmpty
        foreach ($id in @('BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo')) {
            $advanced | Should -Match ('x:Name="' + $id + '"')
        }
    }

    It 'Customize is the only writable identity home' {
        $customize = [regex]::Match($script:ShellSrc, 'x:Name="CustomizePanel"[\s\S]*?(?=x:Name="BrainPanel")').Value
        $customize | Should -Match 'only place'
        foreach ($id in @('CustomizeNameBox','CustomizeColourCombo','CustomizePersonalityCombo','CustomizePersonaBox')) {
            $customize | Should -Match ('x:Name="' + $id + '"')
        }
    }

    It 'Privacy keeps three deletion actions and explains that they cannot be undone' {
        $privacy = [regex]::Match($script:ShellSrc, 'x:Name="PrivacyPanel"[\s\S]*?</StackPanel>').Value
        foreach ($id in @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton','PrivacyStatusText')) {
            $privacy | Should -Match ('x:Name="' + $id + '"')
        }
        $privacy | Should -Match 'cannot be undone'
    }

    It 'Onboarding keeps plain route choices and hides raw setup behind Advanced setup' {
        $script:WizardSrc | Should -Match 'x:Name="BrainBuiltIn"'
        $script:WizardSrc | Should -Match 'x:Name="BrainCustom"'
        $script:WizardSrc | Should -Match 'x:Name="BrainOpenCodeLocal"'
        $script:WizardSrc | Should -Match 'x:Name="BrainOpenCodeRemote"'
        $advanced = [regex]::Match($script:WizardSrc, '<Expander Header="Advanced setup"[\s\S]*?</Expander>').Value
        $advanced | Should -Not -BeNullOrEmpty
        $advanced | Should -Match 'x:Name="EndpointRow"'
        $advanced | Should -Match 'x:Name="OpenCodeRow"'
        $script:WizardSrc | Should -Match 'open Advanced setup'
    }

    It 'owns voice in Settings and brain fields in Brain through the surface contract' {
        $settings = Get-SlopDestinationContract -Name 'Settings'
        $brain = Get-SlopDestinationContract -Name 'Brain'
        @($settings.Editable) | Should -Be @('VoiceEnabledCheck','VoiceLanguageCombo','VoiceMaxSecondsBox')
        @($brain.Editable) | Should -Contain 'BrainAgentIdBox'
        @($brain.Editable) | Should -Contain 'BrainModelBox'
        $map = Get-SlopDestinationMap
        $map.Settings | Should -Contain 'Companion'
        $map.Settings | Should -Contain 'Effective route'
        $map.Brain | Should -Contain 'Where answers come from'
        $map.Brain | Should -Contain 'Advanced'
    }

    It 'never reports success into a hidden chat bubble' {
        $script:ShellSrc | Should -Not -Match "Add-SlopThoughtBubble -Text '[^']*saved"
        $script:ShellSrc | Should -Not -Match 'Add-SlopThoughtBubble[\s\S]{0,120}Settings saved'
    }
}
