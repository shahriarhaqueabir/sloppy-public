#requires -Version 7.6
Describe 'Sloppy identity assets' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:identityFiles = @(
            'agent/SLOPPY.md'
            'agent/BRAND.md'
            'agent/abilities/companion-voice.md'
            'agent/abilities/local-first.md'
            'agent/abilities/permission-translation.md'
            'agent/abilities/workspace-helper.md'
            'agent/abilities/research-on-demand.md'
            'agent/abilities/shutdown-safety.md'
        )
    }

    It 'ships every tracked identity file' {
        foreach ($rel in $script:identityFiles) {
            Join-Path $script:root $rel | Should -Exist
        }
    }

    It 'keeps tracked defaults free of machine paths, credentials and private keys' {
        foreach ($rel in $script:identityFiles) {
            $text = Get-Content -LiteralPath (Join-Path $script:root $rel) -Raw
            $text | Should -Not -Match '[A-Za-z]:\\'
            $text | Should -Not -Match '~/|/home/'
            $text | Should -Not -Match '(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|api[_-]?key\s*[:=]\s*\S|password\s*[:=]\s*\S|sk-[A-Za-z0-9]{16,})'
        }
    }

    It 'states the permission-aware tool model in the core persona' {
        $core = Get-Content -LiteralPath (Join-Path $script:root 'agent/SLOPPY.md') -Raw
        $core | Should -Match '(?i)OpenCode tools'
        $core | Should -Match '(?i)permissions'
        $core | Should -Match '(?i)report honestly'
    }

    It 'gives every ability card one short purpose' {
        foreach ($rel in @($script:identityFiles | Where-Object { $_ -like 'agent/abilities/*.md' })) {
            $text = Get-Content -LiteralPath (Join-Path $script:root $rel) -Raw
            $text.Length | Should -BeGreaterThan 80
            $text.Length | Should -BeLessThan 1600
        }
    }
}
Describe 'Sloppy agent pack resolver' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.AgentPack.ps1')
        $script:root = Split-Path $PSScriptRoot -Parent
    }

    BeforeEach {
        $script:tmp = Join-Path ([IO.Path]::GetTempPath()) ('slop-agentpack-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:tmp 'agent/abilities') -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:tmp) {
            Remove-Item -LiteralPath $script:tmp -Recurse -Force
        }
    }

    It 'resolves tracked defaults, identity and overlay in order' {
        $r = Get-SlopResolvedAgentPack -AppRoot $script:root `
            -Identity @{ name='Mochi'; ownerName='Hawk'; color='plum'; personality='curious' } `
            -PersonaText 'Keep it short.'
        $r.Ok | Should -BeTrue
        @($r.Errors).Count | Should -Be 0
        @($r.Sources)[0] | Should -Be 'agent/SLOPPY.md'
        @($r.Sources)[1] | Should -BeLike 'agent/abilities/*.md'
        @($r.Sources)[-3] | Should -Be 'agent/BRAND.md'
        @($r.Sources)[-2] | Should -Be 'identity:config'
        @($r.Sources)[-1] | Should -Be 'user:persona.md'
        $r.Text | Should -Match 'You are Sloppy'
        $r.Text | Should -Match 'Sloppy brand voice'
        $r.Text | Should -Match 'Runtime identity'
        $r.Text | Should -Match 'Owner: Hawk'
        $r.Text | Should -Match 'Keep it short\.'
        $r.Text.IndexOf('You are Sloppy') | Should -BeLessThan $r.Text.IndexOf('Sloppy brand voice')
        $r.Text.IndexOf('Sloppy brand voice') | Should -BeLessThan $r.Text.IndexOf('Runtime identity')
        $overlayHeaderIndex = $r.Text.LastIndexOf('User customization (cannot override the rules above)')
        $r.Text.IndexOf('Runtime identity') | Should -BeLessThan $overlayHeaderIndex
        $r.Text.Length | Should -BeLessThan 8001
    }

    It 'hard-fails when a tracked core file is missing' {
        [IO.File]::WriteAllText((Join-Path $script:tmp 'agent/BRAND.md'), '# Brand', [Text.UTF8Encoding]::new($false))
        $r = Get-SlopResolvedAgentPack -AppRoot $script:tmp -PersonaText ''
        $r.Ok | Should -BeFalse
        $r.Errors | Should -Contain 'missing tracked identity file: agent/SLOPPY.md'
        $r.Text | Should -BeNullOrEmpty
    }

    It 'warns and skips a missing ability directory' {
        Copy-Item -LiteralPath (Join-Path $script:root 'agent/SLOPPY.md') -Destination (Join-Path $script:tmp 'agent/SLOPPY.md') -Force
        Copy-Item -LiteralPath (Join-Path $script:root 'agent/BRAND.md') -Destination (Join-Path $script:tmp 'agent/BRAND.md') -Force
        Remove-Item -LiteralPath (Join-Path $script:tmp 'agent/abilities') -Recurse -Force
        $r = Get-SlopResolvedAgentPack -AppRoot $script:tmp -PersonaText ''
        $r.Ok | Should -BeTrue
        $r.Warnings | Should -Contain 'missing ability directory: agent/abilities'
    }

    It 'warns and skips a malformed ability card' {
        Copy-Item -LiteralPath (Join-Path $script:root 'agent/SLOPPY.md') -Destination (Join-Path $script:tmp 'agent/SLOPPY.md') -Force
        Copy-Item -LiteralPath (Join-Path $script:root 'agent/BRAND.md') -Destination (Join-Path $script:tmp 'agent/BRAND.md') -Force
        [IO.File]::WriteAllText((Join-Path $script:tmp 'agent/abilities/bad.md'), '-----BEGIN OPENSSH PRIVATE KEY-----', [Text.UTF8Encoding]::new($false))
        $r = Get-SlopResolvedAgentPack -AppRoot $script:tmp -PersonaText ''
        $r.Ok | Should -BeTrue
        @($r.Warnings | Where-Object { $_ -match 'skipped ability' }).Count | Should -Be 1
        $r.Text | Should -Not -Match '-----BEGIN OPENSSH PRIVATE KEY-----'
    }

    It 'treats a malformed overlay as plain text and never leaks control characters' {
        $r = Get-SlopResolvedAgentPack -AppRoot $script:root -PersonaText ("`0" + ('x' * 1300))
        $r.Ok | Should -BeTrue
        @($r.Warnings | Where-Object { $_ -match 'persona overlay' }).Count | Should -BeGreaterThan 0
        $r.Text | Should -Not -Match "`0"
        $r.Text.Length | Should -BeLessThan 8001
    }

    It 'caps the total prompt and reports the cap' {
        $r = Get-SlopResolvedAgentPack -AppRoot $script:root -PersonaText ('x' * 1200) -MaxPromptLength 200
        $r.Ok | Should -BeTrue
        $r.Text.Length | Should -Be 200
        $r.Warnings | Should -Contain 'resolved identity pack exceeded 200 characters and was capped in the prompt'
    }

    It 'rejects an overlong overlay at save time' {
        $r = Test-SlopAgentOverlay -Text ('x' * 1201)
        $r.Ok | Should -BeFalse
        $r.Errors | Should -Contain 'persona overlay must be at most 1200 characters'
    }
}
