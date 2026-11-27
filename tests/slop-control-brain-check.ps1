#Requires -Version 7.4
<#
.SYNOPSIS
  Pester gate for stopslop brain cleanup. Only llama-server processes launched
  from this Sloppy install with the Sloppy alias are in scope.
#>
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

Describe 'Slop control leftover brain cleanup' {
    BeforeAll {
        $script:ScriptPath = Join-Path $PSScriptRoot '../tools/slop-control.ps1'
        . $script:ScriptPath -Action Status | Out-Null
        $script:ControlSource = Get-Content -LiteralPath $script:ScriptPath -Raw
        $script:StopBody = [regex]::Match(
            $script:ControlSource,
            "    'Stop' \{(?<body>[\s\S]*?)\n    \}"
        ).Groups['body'].Value
        $script:RepoPath = Split-Path $PSScriptRoot -Parent
    }

    It 'recognizes a llama-server launched from this Sloppy runtime with the Sloppy alias' {
        $cmd = '"' + $script:RepoPath + '\runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe" --model "' +
            $script:RepoPath + '\runtime\models\Qwen3.5-2B-Q4_K_M.gguf" --host 127.0.0.1 --port 18080 --alias sloppy'
        Test-SlopOwnedBrainCommandLine -CommandLine $cmd -Repo $script:RepoPath | Should -BeTrue
    }

    It 'does not claim a brain launched from another repository' {
        $cmd = '"D:\other\app\runtime\llama-server.exe" --model D:\other\app\models\model.gguf --alias sloppy'
        Test-SlopOwnedBrainCommandLine -CommandLine $cmd -Repo $script:RepoPath | Should -BeFalse
    }

    It 'does not claim an unrelated llama-server with a different alias' {
        $cmd = '"' + $script:RepoPath + '\runtime\llama-server.exe" --model ' +
            $script:RepoPath + '\runtime\models\other.gguf --alias something-else'
        Test-SlopOwnedBrainCommandLine -CommandLine $cmd -Repo $script:RepoPath | Should -BeFalse
    }

    It 'stops brain processes as part of Stop, not just the app process' {
        $script:StopBody | Should -Not -Be ''
        $script:StopBody | Should -Match 'Get-SlopBrainProcesses'
    }
}
