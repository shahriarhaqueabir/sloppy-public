# tests/slop-hygiene-check.ps1
# Portable repo hygiene: no personal paths, honest Whisper claim, ignored data,
# single module load order, and a doc claim that matches the guarded .muted test.
#requires -Version 7.6
Import-Module Pester -MinimumVersion 6.0

$root = Split-Path -Parent $PSScriptRoot
$architecture = Get-Content (Join-Path $root 'docs/architecture.md') -Raw
$qwenPlan = Get-Content (Join-Path $root 'docs/plans/2026-11-25-tier1-qwen-brain-switch-plan.md') -Raw
$provider = Get-Content (Join-Path $root 'src/Slop.Provider.ps1') -Raw
$gitignore = Get-Content (Join-Path $root '.gitignore') -Raw

Describe 'Sloppy repo hygiene' {
    It 'contains no personal absolute user paths in tracked text files' {
        Push-Location $root
        try {
            $hits = @(git grep -I -l -F -- 'C:\Users\shahr' 2>$null)
            $hits.Count | Should -Be 0
        } finally {
            Pop-Location
        }
    }

    It 'states the tracked Whisper artifacts honestly in architecture and the Qwen plan' {
        foreach ($doc in @($architecture, $qwenPlan)) {
            $doc | Should -Match 'CLI and DLLs are bundled'
            $doc | Should -Match 'ggml-small\.bin.*downloaded and checksum-verified during setup'
            $doc | Should -Not -Match 'does not include.*whisper-cli\.exe'
            $doc | Should -Not -Match 'supply them under.*runtime/whisper'
        }
    }

    It 'keeps local data ignored without touching it' {
        $gitignore | Should -Match '(?m)^/data/\s*$'
    }

    It 'does not re-dot-source modules that Slop.ps1 already loads in order' {
        $providerSrc = Get-Content (Join-Path $root 'src/Slop.Provider.ps1') -Raw
        $providerSrc | Should -Not -Match 'Slop\.LocalModel\.ps1'
        $providerSrc | Should -Not -Match 'Slop\.Route\.ps1'
    }

    It 'describes the muted policy file as absent and guarded, not retained' {
        $architecture | Should -Not -Match 'retained as'
        $architecture | Should -Match 'was removed from the active config'
        $architecture | Should -Match 'not shipped in this checkout'
    }
}
