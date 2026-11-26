#requires -Version 7.6
Describe 'Slop.Audio' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Audio.ps1')
    }

    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('slop-audio-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'runtime\whisper\models') -Force | Out-Null
        $script:Cli = Join-Path $script:Root 'runtime\whisper\whisper-cli.cmd'
        Set-Content -LiteralPath $script:Cli -Value @'
@echo off
echo [00:00:00.000 --^> 00:00:01.000] hello from whisper
echo.
echo second line
'@ -Encoding ascii
        $script:Model = Join-Path $script:Root 'runtime\whisper\models\ggml-small.bin'
        [IO.File]::WriteAllBytes($script:Model, [byte[]](1,2,3,4))
        $script:Wav = Join-Path $script:Root 'utterance.wav'
        [IO.File]::WriteAllBytes($script:Wav, [byte[]](1,2,3,4,5,6,7,8))
        $script:Paths = Get-SlopWhisperPaths -InstallRoot $script:Root `
            -CliFile 'runtime\whisper\whisper-cli.cmd' `
            -ModelFile 'runtime\whisper\models\ggml-small.bin'
    }

    AfterEach {
        Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'resolves relative and absolute paths without normalizing the user config' {
        $script:Paths.Cli | Should -Be (Join-Path $script:Root 'runtime\whisper\whisper-cli.cmd')
        $script:Paths.Model | Should -Be $script:Model
        $absolute = Get-SlopWhisperPaths -InstallRoot $script:Root -CliFile $script:Cli -ModelFile $script:Model
        $absolute.Cli | Should -Be $script:Cli
    }

    It 'reports readiness and names each missing artifact' {
        (Test-SlopWhisperReady -Paths $script:Paths).Ok | Should -BeTrue
        Remove-Item -LiteralPath $script:Cli -Force
        $missingCli = Test-SlopWhisperReady -Paths $script:Paths
        $missingCli.Ok | Should -BeFalse
        ($missingCli.Errors -join '; ') | Should -Match 'whisperRuntimeFile'
    }

    It 'parses timestamps, blank lines and plain text into one transcript' {
        Convert-SlopWhisperOutput -Raw "[00:00:00.000 --> 00:00:01.000] hello`r`n`r`n  world  " | Should -Be 'hello world'
        Convert-SlopWhisperOutput -Raw 'plain text' | Should -Be 'plain text'
        Convert-SlopWhisperOutput -Raw '' | Should -Be ''
    }

    It 'transcribes through a fake whisper-cli stand-in' {
        $result = Invoke-SlopWhisperTranscription -Paths $script:Paths -WavPath $script:Wav -Language 'en' -TimeoutSeconds 10
        $result.Ok | Should -BeTrue
        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be 'hello from whisper second line'
    }

    It 'reports an integrity failure without throwing' {
        $hash = (Get-FileHash -LiteralPath $script:Model -Algorithm SHA1).Hash.ToLowerInvariant()
        (Test-SlopWhisperIntegrity -Paths $script:Paths -ExpectedSha1 $hash).Ok | Should -BeTrue
        $bad = Test-SlopWhisperIntegrity -Paths $script:Paths -ExpectedSha1 '0000000000000000000000000000000000000000'
        $bad.Ok | Should -BeFalse
        $bad.Reason | Should -Match 'SHA-1'
    }

    It 'exposes a deterministic install root and readiness text for UI tests' {
        $env:SLOP_TEST_INSTALL_ROOT = $script:Root
        Get-SlopVoiceInstallRoot | Should -Be $script:Root
        $cfg = @{
            whisperRuntimeFile = 'runtime\whisper\whisper-cli.cmd'
            whisperModelFile   = 'runtime\whisper\models\ggml-small.bin'
        }
        Get-SlopVoiceReadinessText -Config $cfg | Should -Be 'Ready'
        Remove-Item -LiteralPath $script:Model -Force
        Get-SlopVoiceReadinessText -Config $cfg | Should -Match 'whisperModelFile'
    }

    It 'honors an explicit app root for the voice install root' {
        Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue
        $appRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-voice-root-' + [guid]::NewGuid().ToString('N'))
        try {
            Get-SlopVoiceInstallRoot -InstallRoot $appRoot | Should -Be ([IO.Path]::GetFullPath($appRoot))
        } finally {
            if (Test-Path -LiteralPath $appRoot) { Remove-Item -LiteralPath $appRoot -Recurse -Force }
        }
    }

    It 'offers a bounded language list including auto' {
        $langs = @(Get-SlopWhisperLanguages)
        $langs[0] | Should -Be 'auto'
        $langs | Should -Contain 'en'
        $langs | Should -Contain 'zh'
    }

    It 'defaults the voice root to the canonical app root' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:Root
            Get-SlopVoiceInstallRoot | Should -Be ([IO.Path]::GetFullPath($script:Root))
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }
}
