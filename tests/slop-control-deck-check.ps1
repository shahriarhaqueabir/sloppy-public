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
        $contract.Actions | Should -Contain 'DeleteAllButton'
        $contract.Actions | Should -Contain 'DeleteOpenCodeButton'
        $script:ShellSrc | Should -Match 'Show-SlopConfirm[\s\S]{0,400}DeleteAllButton'
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
}
