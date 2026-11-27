# tests/slop-hygiene-check.ps1
# Portable repo hygiene: no personal paths, honest Whisper claim, ignored data,
# single module load order, and a doc claim that matches the guarded .muted test.
#requires -Version 7.6
Import-Module Pester -MinimumVersion 6.0

Describe 'Sloppy repo hygiene' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        $script:architecture = Get-Content (Join-Path $script:root 'docs/architecture.md') -Raw
        $script:qwenPlan = Get-Content (Join-Path $script:root 'docs/plans/2026-11-25-tier1-qwen-brain-switch-plan.md') -Raw
        $script:gitignore = Get-Content (Join-Path $script:root '.gitignore') -Raw
    }

    It 'contains no personal absolute user paths in tracked text files' {
        Push-Location $script:root
        try {
            $personal = "C:$([char]92)Users$([char]92)shahr"
            $hits = @(git grep -I -l -F -- $personal 2>$null)
            $hits.Count | Should -Be 0
        } finally {
            Pop-Location
        }
    }

    It 'states the tracked Whisper artifacts honestly in architecture and the Qwen plan' {
        foreach ($doc in @($script:architecture, $script:qwenPlan)) {
            $doc | Should -Match 'CLI and DLLs are bundled'
            $doc | Should -Match 'ggml-small\.bin.*downloaded and checksum-verified during setup'
            $doc | Should -Not -Match 'does not include.*whisper-cli\.exe'
            $doc | Should -Not -Match 'supply them under.*runtime/whisper'
        }
    }

    It 'keeps local data ignored without touching it' {
        $script:gitignore | Should -Match '(?m)^/data/\s*$'
    }

    It 'does not re-dot-source modules that Slop.ps1 already loads in order' {
        $providerSrc = Get-Content (Join-Path $script:root 'src/Slop.Provider.ps1') -Raw
        $providerSrc | Should -Not -Match 'Slop\.LocalModel\.ps1'
        $providerSrc | Should -Not -Match 'Slop\.Route\.ps1'
    }

    It 'describes the muted policy file as absent and guarded, not retained' {
        $script:architecture | Should -Not -Match 'retained as'
        $script:architecture | Should -Match 'was removed from\s+the active config'
        $script:architecture | Should -Match 'not shipped in this checkout'
    }
}
