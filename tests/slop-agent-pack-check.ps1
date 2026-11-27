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
