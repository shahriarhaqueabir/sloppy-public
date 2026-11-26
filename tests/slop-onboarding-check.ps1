#requires -Version 7.6
Describe 'Slop.Onboarding' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Route.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1')
    }

    It 'offers exactly four persona presets with non-empty live preview copy' {
        $presets = @(Get-SlopPersonaPresets)
        (@($presets.Id | Sort-Object) -join ',') | Should -Be 'calm,curious,playful,professional'
        foreach ($p in $presets) { [string]::IsNullOrWhiteSpace([string]$p.Sample) | Should -BeFalse }
    }

    It 'writes the companion name, owner, preset voice and custom instructions' {
        $md = New-SlopPersonaMarkdown -Preset 'curious' -Name 'Mochi' -OwnerName 'the user' -CustomText '  Keep it short.  '
        $md | Should -Match 'You are Mochi'
        $md | Should -Match 'goes by the user'
        $md | Should -Match 'Lead with genuine curiosity'
        $md | Should -Match 'Additional instructions'
        $md | Should -Match 'Keep it short\.'
        $md | Should -Not -Match '\sKeep it short\.  '
    }

    It 'omits the owner sentence and custom header when neither was supplied' {
        $md = New-SlopPersonaMarkdown -Preset 'calm' -Name 'Sloppy' -CustomText ''
        $md | Should -Not -Match 'goes by'
        $md | Should -Not -Match 'Additional instructions'
    }

    It 'produces a distinct voice for every preset' {
        $bodies = @(Get-SlopPersonaPresets | ForEach-Object {
            New-SlopPersonaMarkdown -Preset $_.Id -Name 'X'
        })
        ($bodies | Select-Object -Unique).Count | Should -Be 4
    }

    It 'ends with one newline and never emits CRLF' {
        $md = New-SlopPersonaMarkdown -Preset 'professional' -Name 'X'
        $md.EndsWith("`n") | Should -BeTrue
        $md.EndsWith("`n`n") | Should -BeFalse
        $md | Should -Not -Match "`r"
    }

    It 'generates the swatches from the config palette and keeps the honest brain note' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Match 'Get-SlopIdentityColors'
        $src | Should -Match 'Get-SlopIdentityColor -ColorKey'
        $src | Should -Match 'foreach \(\$entry in \(Get-SlopIdentityColors\)'
        $src | Should -Match 'Full CLI brains arrive in the next release\. For now, enter any OpenAI-compatible local server URL\.'
        $src | Should -Match 'BrainCustom'
        $src | Should -Match 'BrainOpenCodeLocal'
        $src | Should -Match 'BrainOpenCodeRemote'
    }

    It 'returns a complete fallback result when a first run is dismissed' {
        $result = New-SlopFallbackOnboardingResult -Config @{ name = 'Pip' }
        (Test-SlopConfig -Config $result).Ok | Should -BeTrue
        $result.personaText | Should -Match 'You are Pip'
        $result.brain | Should -Be 'builtin'
    }

    It 'keeps four screens and exposes voice controls on Screen 4' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Match 'x:Name="Screen4"'
        $src | Should -Match 'x:Name="VoiceEnabledCheck"'
        $src | Should -Match 'x:Name="VoiceLanguageCombo"'
        $src | Should -Match 'x:Name="VoiceReadyText"'
        $src | Should -Match 'Get-SlopWhisperLanguages'
        $src | Should -Match 'Get-SlopVoiceReadinessText -Config \$Config'
        $src | Should -Not -Match 'ValidateRange\(1,5\)'
    }

    It 'writes voice settings from the wizard into the version 3 result' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Match '\$result\.voiceEnabled = \[bool\]\$VoiceEnabledCheck\.IsChecked'
        $src | Should -Match '\$result\.whisperLanguage = \(\[string\]\$VoiceLanguageCombo\.SelectedItem\)\.Trim\(\)\.ToLowerInvariant\(\)'
        $fallback = New-SlopFallbackOnboardingResult -Config @{ name = 'Pip'; voiceEnabled = $true }
        (Test-SlopConfig -Config $fallback).Ok | Should -BeTrue
        $fallback.version | Should -Be 3
        $fallback.voiceEnabled | Should -BeTrue
        $fallback.whisperLanguage | Should -Be 'auto'
    }
}
