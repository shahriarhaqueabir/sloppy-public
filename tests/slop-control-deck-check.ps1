#requires -Version 7.6
Describe 'Slop control deck' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.ControlDeck.ps1')
        $script:ShellSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
        $script:ChatSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1') -Raw
    }

    It 'exposes exactly the six accepted sections' {
        $sections = Get-SlopControlDeckSections
        @($sections).Count | Should -Be 6
        @($sections).Name | Should -Be @('Overview','Settings','Data','Tools & Skills','Under the hood','Exit')
    }

    It 'declares the six capability toggles in the deck' {
        $toggles = Get-SlopControlDeckToggleIds
        @($toggles).Count | Should -Be 6
        $toggles | Should -Contain 'WorkspaceFilesToggle'
        $toggles | Should -Contain 'ExternalFoldersToggle'
    }

    It 'does not expose copy, clipboard, read-aloud, or raw permission JSON controls' {
        foreach ($src in @($script:ShellSrc, $script:ChatSrc)) {
            $src | Should -Not -Match 'CopyButton'
            $src | Should -Not -Match 'Clipboard'
            $src | Should -Not -Match 'ReadAloud'
            $src | Should -Not -Match 'PermissionJson'
        }
    }

    It 'uses the existing deletion scope contracts in Data' {
        . (Join-Path $PSScriptRoot '../src/Slop.Surfaces.ps1')
        $contract = Get-SlopDestinationContract -Name Privacy
        $contract.Actions | Should -Contain 'DeleteConversationButton'
        $contract.Actions | Should -Contain 'DeleteSessionButton'
        $script:ShellSrc | Should -Match 'Show-SlopConfirm[\s\S]{0,6000}DeleteConversationButton'
    }

    It 'shows copy-free Overview and read-only Under the hood state' {
        $script:ChatSrc | Should -Match 'x:Name="DeckOverviewText"'
        $script:ChatSrc | Should -Match 'x:Name="DeckConversationLengthText"'
        $script:ChatSrc | Should -Match 'x:Name="DeckUnderHoodText"[^>]*IsReadOnly="True"'
    }

    It 'opens by default in Full and reveals from Extended via a header button' {
        $script:ShellSrc | Should -Match 'x:Name="ControlDeckButton"'
        $script:ShellSrc | Should -Match '\$script:ChatDeckOpen\s*=\s*\$true'
        $script:ShellSrc | Should -Match "ChatMode -eq 'Full'[\s\S]{0,200}ChatDeckOpen"
    }

    It 'shows disclosure copy for web and shell toggles' {
        $script:ChatSrc | Should -Match 'x:Name="WebAccessDisclosureText"'
        $script:ChatSrc | Should -Match 'x:Name="ShellCommandsDisclosureText"'
        $script:ChatSrc | Should -Match 'beyond this PC'
        $script:ChatSrc | Should -Match 'change files'
    }

    It 'declares six section buttons and six toggle controls in chat XAML' {
        foreach ($name in @('DeckOverviewButton','DeckSettingsButton','DeckDataButton','DeckToolsButton','DeckUnderHoodButton','DeckExitButton',
                            'WorkspaceFilesToggle','WebAccessToggle','ShellCommandsToggle','SkillsPluginsToggle','SubagentsTasksToggle','ExternalFoldersToggle')) {
            $script:ChatSrc | Should -Match ([regex]::Escape('x:Name="' + $name + '"'))
        }
    }

    It 'sizes the deck body without squeezing transcript or composer' {
        Get-SlopDeckBodyHeight -WindowHeight 760 -DeckOpen $true | Should -Be 220
        Get-SlopDeckBodyHeight -WindowHeight 410 -DeckOpen $true | Should -Be 92
        Get-SlopDeckBodyHeight -WindowHeight 200 -DeckOpen $true | Should -Be 0
        Get-SlopDeckBodyHeight -WindowHeight 760 -DeckOpen $false | Should -Be 0
    }

    It 'builds a safe deck settings snapshot from a config' {
        $cfg = @{
            voiceEnabled = $true; whisperLanguage = 'de'; voiceMaxSeconds = 45
            brain = 'opencode'; model = 'beam-free'; modelName = 'beam-free'
        }
        $snapshot = Get-SlopDeckSettingsSnapshot -Config $cfg -ConfigPath 'C:/fixture/config.json' -Route 'OpenCode' -Readiness 'Ready'
        $snapshot.ConfigAvailable | Should -BeTrue
        $snapshot.VoiceEnabled | Should -BeTrue
        $snapshot.VoiceLanguage | Should -Be 'de'
        $snapshot.VoiceMaxSeconds | Should -Be 45
        $snapshot.VoiceReadyText | Should -Be 'Ready'
        $snapshot.RouteText | Should -Be 'OpenCode'
        $snapshot.Brain | Should -Be 'opencode'
        $snapshot.Model | Should -Be 'beam-free'
        $snapshot.DataPath | Should -Be 'C:/fixture/config.json'
    }

    It 'uses safe defaults when config is missing' {
        $snapshot = Get-SlopDeckSettingsSnapshot -Config $null -ConfigPath '' -Route '' -Readiness ''
        $snapshot.ConfigAvailable | Should -BeFalse
        $snapshot.VoiceEnabled | Should -BeFalse
        $snapshot.VoiceLanguage | Should -Be 'auto'
        $snapshot.VoiceMaxSeconds | Should -Be 30
        $snapshot.Brain | Should -Be 'unset'
        $snapshot.Model | Should -Be 'unset'
        $snapshot.DataPath | Should -Be 'unavailable'
    }

    It 'validates deck voice edits before a config write' {
        $cfg = @{ voiceEnabled = $false; whisperLanguage = 'auto'; voiceMaxSeconds = 30 }
        $good = Get-SlopDeckVoiceEdit -Config $cfg -Language 'DE' -MaxSeconds '45'
        $good.Ok | Should -BeTrue
        $good.Config.whisperLanguage | Should -Be 'de'
        $good.Config.voiceMaxSeconds | Should -Be 45
        $cfg.whisperLanguage | Should -Be 'auto'
        (Get-SlopDeckVoiceEdit -Config $cfg -Language 'auto' -MaxSeconds '9').Ok | Should -BeFalse
        (Get-SlopDeckVoiceEdit -Config $cfg -Language 'auto' -MaxSeconds '121').Ok | Should -BeFalse
        (Get-SlopDeckVoiceEdit -Config $cfg -Language 'auto' -MaxSeconds 'many').Ok | Should -BeFalse
        (Get-SlopDeckVoiceEdit -Config $null -Language 'auto' -MaxSeconds '30').Ok | Should -BeFalse
    }

    It 'builds model edit arguments that preserve other brain fields' {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        # Set-SlopConfigBrain validates the whole config, so start from the real default
        # and override only route/voice fields under test.
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'opencode'
        $cfg.provider = 'opencode-go'
        $cfg.providerLocality = 'remote'
        $cfg.endpointUrl = 'http://127.0.0.1:28894'
        $cfg.model = 'old'
        $cfg.modelName = 'old'
        $cfg.agentId = 'sloppy'
        $cfg.capabilityProfile = 'companion'
        $cfg.voiceEnabled = $true
        $cfg.whisperLanguage = 'de'
        $cfg.voiceMaxSeconds = 45
        $edit = Get-SlopDeckModelEditArguments -Config $cfg -Model 'new-model'
        $edit.Ok | Should -BeTrue
        $edit.Brain | Should -Be 'opencode'
        $edit.Provider | Should -Be 'opencode-go'
        $edit.EndpointUrl | Should -Be 'http://127.0.0.1:28894'
        $edit.AgentId | Should -Be 'sloppy'
        $edit.CapabilityProfile | Should -Be 'companion'
        $result = Set-SlopConfigBrain -Config $cfg `
            -Brain $edit.Brain -Provider $edit.Provider -ProviderLocality $edit.ProviderLocality `
            -EndpointUrl $edit.EndpointUrl -Model $edit.Model -AgentId $edit.AgentId `
            -CapabilityProfile $edit.CapabilityProfile
        $result.Ok | Should -BeTrue
        $result.Config.voiceEnabled | Should -BeTrue
        $result.Config.whisperLanguage | Should -Be 'de'
        $result.Config.voiceMaxSeconds | Should -Be 45
        $result.Config.model | Should -Be 'new-model'
        (Get-SlopDeckModelEditArguments -Config $cfg -Model '').Ok | Should -BeFalse
        (Get-SlopDeckModelEditArguments -Config $null -Model 'new-model').Ok | Should -BeFalse
    }
}
