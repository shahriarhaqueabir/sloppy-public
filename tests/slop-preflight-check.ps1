#requires -Version 7.6
Describe 'Slop preflight' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')
        $script:Tool = Join-Path $PSScriptRoot '../tools/slop-preflight.ps1'
        . $script:Tool
    }

    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('slop-preflight-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\llama-b12676-bin-win-cuda-13.5-x64') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\whisper\models') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\models') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Root 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe') -Value ('x' * 2048) -Encoding ascii
        Set-Content -LiteralPath (Join-Path $script:Root 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf') -Value ('x' * 2048) -Encoding ascii
        Set-Content -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Value 'stub' -Encoding ascii
        $script:Model = Join-Path $script:Root 'runtime\whisper\models\ggml-small.bin'
        [IO.File]::WriteAllBytes($script:Model, [byte[]](1,2,3,4,5,6,7,8))
        $script:Hash = (Get-FileHash -LiteralPath $script:Model -Algorithm SHA1).Hash.ToLowerInvariant()
        $script:ConfigPath = Join-Path $script:Root 'config.json'
        Write-SlopConfig -Config (New-SlopDefaultConfig) -ConfigPath $script:ConfigPath
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'reports a fully stubbed Tier 1 install as ready' {
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash
        $report.Ok | Should -BeTrue
        @($report.Errors).Count | Should -Be 0
        ($report.Lines -join "`n") | Should -Match '\[OK\] config: config version 3'
        ($report.Lines -join "`n") | Should -Match '\[OK\] Whisper model SHA-1'
        ($report.Lines -join "`n") | Should -Match '\[OK\] Qwen model'
    }

    It 'names a missing Whisper CLI and fails closed' {
        Remove-Item -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Force
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash
        $report.Ok | Should -BeFalse
        ($report.Errors -join '; ') | Should -Match 'whisperRuntimeFile'
    }

    It 'reports a model hash mismatch' {
        $report = Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 '0000000000000000000000000000000000000000'
        $report.Ok | Should -BeFalse
        ($report.Lines -join "`n") | Should -Match 'Whisper model SHA-1: expected'
    }

    It 'uses exit code 1 for a missing artifact and 0 with -ReportOnly' {
        Remove-Item -LiteralPath (Join-Path $script:Root 'runtime\whisper\whisper-cli.exe') -Force
        & pwsh -NoProfile -File $script:Tool -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        & pwsh -NoProfile -File $script:Tool -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash -ReportOnly 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'never writes user config during a report' {
        $before = [IO.File]::ReadAllBytes($script:ConfigPath)
        Invoke-SlopPreflight -InstallRoot $script:Root -ConfigPath $script:ConfigPath -ExpectedModelSha1 $script:Hash | Out-Null
        $after = [IO.File]::ReadAllBytes($script:ConfigPath)
        ($before -join ',') | Should -Be ($after -join ',')
    }

    It 'resolves the app root from the hidden override when no root is passed' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $TestDrive
            $report = Invoke-SlopPreflight -ConfigPath (Join-Path $TestDrive 'config.json')
            $report.InstallRoot | Should -Be ([IO.Path]::GetFullPath($TestDrive))
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }

    It 'does not read SLOP_TEST_APPDATA anywhere in tools' {
        $files = Get-ChildItem (Join-Path $PSScriptRoot '../tools') -Filter '*.ps1'
        foreach ($f in $files) {
            (Get-Content $f.FullName -Raw) | Should -Not -Match 'SLOP_TEST_APPDATA'
        }
    }
}
