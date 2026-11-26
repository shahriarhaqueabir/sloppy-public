#requires -Version 7.6
Describe 'Slop.Config' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-config-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'data') -Force | Out-Null
        $script:ConfigPath = Join-Path $script:TestRoot 'data\config.json'
        $script:PersonaPath = Join-Path $script:TestRoot 'data\persona.md'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'honours the disposable install-root override without touching LOCALAPPDATA' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:TestRoot
            Get-SlopAppRoot | Should -Be ([IO.Path]::GetFullPath($script:TestRoot))
            Get-SlopUserDataPath | Should -Be (Join-Path $script:TestRoot 'data')
            Get-SlopConfigPath | Should -Be $script:ConfigPath
            Get-SlopPersonaPath | Should -Be $script:PersonaPath
        } finally {
            if ($null -eq $previous) { Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue }
            else { $env:SLOP_TEST_INSTALL_ROOT = $previous }
        }
    }

    It 'default config passes validation' {
        $result = Test-SlopConfig -Config (New-SlopDefaultConfig)
        $result.Ok | Should -BeTrue
        @($result.Errors).Count | Should -Be 0
    }

    It 'defaults local bundled context and readiness for Qwen3.5-2B' {
        $cfg = New-SlopDefaultConfig
        $cfg.localModelName | Should -Be 'Qwen3.5-2B Q4_K_M'
        $cfg.localModelFile | Should -Match 'Qwen3\.5-2B-Q4_K_M\.gguf$'
        $cfg.localMmprojFile | Should -Be ''
        $cfg.localContextSize | Should -Be 8192
        $cfg.localVisionReady | Should -BeTrue
        $cfg.localAudioReady | Should -BeTrue
    }

    It 'accepts an empty or configured localMmprojFile as valid config' {
        $cfg = New-SlopDefaultConfig
        $cfg.localMmprojFile = ''
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
        $cfg.localMmprojFile = 'models\custom-mmproj.gguf'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }

    It 'accepts allowed localContextSize values and normalizes invalid ones' {
        foreach ($size in 8192,16384,32768) {
            $cfg = New-SlopDefaultConfig
            $cfg.localContextSize = $size
            (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
        }
        $bad = New-SlopDefaultConfig
        $bad.localContextSize = 12345
        (Test-SlopConfig -Config $bad).Ok | Should -BeFalse

        [IO.File]::WriteAllText($script:ConfigPath, '{"name":"Pea","localContextSize":12345}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.localContextSize | Should -Be 8192
    }

    It 'returns six identity colors, none of which is a semantic signal hex' {
        $colors = Get-SlopIdentityColors
        @($colors.Keys).Count | Should -Be 6
        $signals = @('#3B82F6', '#F59E0B', '#22C55E', '#EF4444')
        foreach ($hex in $colors.Values) { $signals | Should -Not -Contain $hex }
        Get-SlopIdentityColor ocean | Should -Be '#6366F1'
        { Get-SlopIdentityColor 'not-a-swatch' } | Should -Throw
    }

    It 'lists both built-in and opt-in brains' {
        $brains = Get-SlopBrains
        $brains | Should -Contain 'builtin'
        $brains | Should -Contain 'custom'
        $brains | Should -Contain 'opencode'
    }

    It 'rejects invalid scalar and enum values' {
        $base = New-SlopDefaultConfig
        $cases = @(
            @{ key='color'; value='not-a-swatch' }
            @{ key='personality'; value='chaotic' }
            @{ key='brain'; value='telepathy' }
            @{ key='name'; value=('x' * 41) }
            @{ key='autostart'; value='yes' }
            @{ key='providerLocality'; value='somewhere' }
            @{ key='providerTier'; value='enterprise' }
            @{ key='capabilityProfile'; value='root' }
            @{ key='agent'; value='not-a-table' }
        )
        foreach ($case in $cases) {
            $cfg = @{} + $base
            $cfg[$case.key] = $case.value
            (Test-SlopConfig -Config $cfg).Ok | Should -BeFalse
        }
    }

    It 'accepts an OpenCode route config' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'opencode'
        $cfg.providerLocality = 'local'
        $cfg.providerTier = 'free'
        $cfg.provider = 'Ollama'
        $cfg.model = 'qwen3:8b'
        $cfg.capabilityProfile = 'companion'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }

    It 'rejects instructions longer than 1200 characters' {
        $cfg = New-SlopDefaultConfig
        $cfg.instructions = 'x' * 1201
        $result = Test-SlopConfig -Config $cfg
        $result.Ok | Should -BeFalse
        $result.Errors | Should -Contain 'instructions must be at most 1200 characters'
    }

    It 'accepts a loopback openCodeBaseUrl and rejects non-loopback or credentialed values' {
        $cfg = New-SlopDefaultConfig
        $cfg.openCodeBaseUrl = 'http://127.0.0.1:28894'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue

        foreach ($bad in @('https://example.com', 'http://localhost:28894?x=1', 'http://user:pass@127.0.0.1:28894', 'http://127.0.0.1:28894#frag')) {
            $badCfg = New-SlopDefaultConfig
            $badCfg.openCodeBaseUrl = $bad
            $result = Test-SlopConfig -Config $badCfg
            $result.Ok | Should -BeFalse
            $result.Errors | Should -Contain 'openCodeBaseUrl must be a loopback http URL without embedded credentials or query data'
        }
    }

    It 'rejects a non-local endpointUrl only for the custom brain' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'custom'
        $cfg.endpointUrl = 'https://example.invalid/v1'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeFalse
        $cfg2 = New-SlopDefaultConfig
        $cfg2.brain = 'opencode'
        $cfg2.endpointUrl = ''
        (Test-SlopConfig -Config $cfg2).Ok | Should -BeTrue
    }

    It 'reports a nonexistent config as absent with defaults' {
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Exists | Should -BeFalse
        $r.Config.name | Should -Be 'Sloppy'
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'ignores unknown keys and fills missing known keys from defaults' {
        [IO.File]::WriteAllText($script:ConfigPath, '{"name":"Pea","futureKey":123}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.name | Should -Be 'Pea'
        $r.Config.color | Should -Be 'ocean'
        $r.Config.brain | Should -Be 'builtin'
        $r.Config.PSObject.Properties.Name | Should -Not -Contain 'futureKey'
    }

    It 'migrates version 0 and version 1 configs to version 2 in memory' {
        foreach ($version in 0, 1) {
            [IO.File]::WriteAllText($script:ConfigPath, ('{{"version":{0},"name":"Pea"}}' -f $version), [Text.UTF8Encoding]::new($false))
            $r = Read-SlopConfig -ConfigPath $script:ConfigPath
            $r.Ok | Should -BeTrue
            $r.Config.version | Should -Be 2
            $r.Config.name | Should -Be 'Pea'
        }
    }

    It 'fails closed on malformed JSON with a plain-language reason' {
        [IO.File]::WriteAllText($script:ConfigPath, '{ not json', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeFalse
        $r.Exists | Should -BeTrue
        $r.Reason | Should -Match 'not valid JSON'
        $r.Config.name | Should -Be 'Sloppy'
    }

    It 'keeps one backup whose content is the first config' {
        $first = New-SlopDefaultConfig
        $first.name = 'First'
        Write-SlopConfig -Config $first -ConfigPath $script:ConfigPath
        $second = New-SlopDefaultConfig
        $second.name = 'Second'
        Write-SlopConfig -Config $second -ConfigPath $script:ConfigPath
        Test-Path -LiteralPath "$script:ConfigPath.bak" | Should -BeTrue
        $bak = Get-Content -LiteralPath "$script:ConfigPath.bak" -Raw | ConvertFrom-Json
        $bak.name | Should -Be 'First'
    }

    It 'refuses to write an invalid config and creates no file' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'not-a-brain'
        { Write-SlopConfig -Config $cfg -ConfigPath $script:ConfigPath } | Should -Throw
        Test-Path -LiteralPath $script:ConfigPath | Should -BeFalse
    }

    It 'quotes and escapes an autostart executable path' {
        $plain = Get-SlopAutostartValue 'C:\Program Files\Sloppy\launch.exe'
        $plain | Should -Be '"C:\Program Files\Sloppy\launch.exe"'
        $tricky = Get-SlopAutostartValue 'C:\Odd"Name\launch.exe'
        $tricky | Should -Match '\\"'
    }

    It 'round-trips Unicode persona text through UTF-8 without BOM' {
        $text = "line one`nline two — café ☕ `n"
        Write-SlopPersona -Text $text -PersonaPath $script:PersonaPath
        Read-SlopPersona -PersonaPath $script:PersonaPath | Should -Be $text
        $bytes = [IO.File]::ReadAllBytes($script:PersonaPath)
        $bytes[0] | Should -Not -Be 0xEF
    }

    It 'defaults voice off with pinned Whisper relative paths' {
        $cfg = New-SlopDefaultConfig
        $cfg.version | Should -Be 3
        $cfg.voiceEnabled | Should -BeFalse
        $cfg.whisperRuntimeFile | Should -Be 'runtime\whisper\whisper-cli.exe'
        $cfg.whisperModelFile | Should -Be 'runtime\whisper\models\ggml-small.bin'
        $cfg.whisperLanguage | Should -Be 'auto'
        $cfg.voiceMaxSeconds | Should -Be 30
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }

    It 'normalizes malformed voice values to safe defaults and preserves valid ones' {
        [IO.File]::WriteAllText($script:ConfigPath, '{"version":2,"voiceEnabled":true,"whisperLanguage":"EN","whisperModelFile":"","voiceMaxSeconds":2}', [Text.UTF8Encoding]::new($false))
        $r = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r.Ok | Should -BeTrue
        $r.Config.voiceEnabled | Should -BeTrue
        $r.Config.whisperLanguage | Should -Be 'auto'
        $r.Config.whisperModelFile | Should -Be 'runtime\whisper\models\ggml-small.bin'
        $r.Config.voiceMaxSeconds | Should -Be 30

        [IO.File]::WriteAllText($script:ConfigPath, '{"version":2,"voiceEnabled":true,"voiceMaxSeconds":45}', [Text.UTF8Encoding]::new($false))
        $r2 = Read-SlopConfig -ConfigPath $script:ConfigPath
        $r2.Ok | Should -BeTrue
        $r2.Config.voiceMaxSeconds | Should -Be 45
    }

    It 'rejects out-of-range voice settings in Test-SlopConfig' {
        $badLanguage = New-SlopDefaultConfig
        $badLanguage.whisperLanguage = 'EN'
        ((Test-SlopConfig -Config $badLanguage).Errors -join '; ') | Should -Match 'whisperLanguage'

        $badSeconds = New-SlopDefaultConfig
        $badSeconds.voiceMaxSeconds = 9
        ((Test-SlopConfig -Config $badSeconds).Errors -join '; ') | Should -Match 'voiceMaxSeconds'

        $badBool = New-SlopDefaultConfig
        $badBool.voiceEnabled = 'yes'
        ((Test-SlopConfig -Config $badBool).Errors -join '; ') | Should -Match 'voiceEnabled'
    }

    It 'Set-SlopConfigIdentity changes identity fields without mutating the input or writing a file' {
        $cfg = New-SlopDefaultConfig
        $r = Set-SlopConfigIdentity -Config $cfg -Name 'Mochi' -Color 'plum' -Personality 'playful'
        $r.Ok | Should -BeTrue
        @($r.Errors).Count | Should -Be 0
        $r.Config.name | Should -Be 'Mochi'
        $r.Config.color | Should -Be 'plum'
        $r.Config.personality | Should -Be 'playful'
        $cfg.name | Should -Be 'Sloppy'
        Test-Path -LiteralPath $script:ConfigPath | Should -BeFalse
    }

    It 'Set-SlopConfigIdentity rejects an invalid swatch' {
        $r = Set-SlopConfigIdentity -Config (New-SlopDefaultConfig) -Name 'Mochi' -Color 'neon' -Personality 'calm'
        $r.Ok | Should -BeFalse
        ($r.Errors -join '; ') | Should -Match 'color'
    }

    It 'Set-SlopConfigBrain makes a valid custom route and clears stale discovered agent metadata' {
        $cfg = New-SlopDefaultConfig
        $cfg.agent = @{ model = 'stale-discovered-model' }
        $r = Set-SlopConfigBrain -Config $cfg -Brain 'custom' -Provider 'ignored' `
            -ProviderLocality 'remote' -ProviderTier 'paid' -EndpointUrl 'http://127.0.0.1:18080/' `
            -Model 'local-model' -AgentId 'ignored' -CapabilityProfile 'power'
        $r.Ok | Should -BeTrue
        @($r.Errors).Count | Should -Be 0
        $r.Config.brain | Should -Be 'custom'
        $r.Config.endpointUrl | Should -Be 'http://127.0.0.1:18080'
        $r.Config.model | Should -Be 'local-model'
        $r.Config.modelName | Should -Be 'local-model'
        $r.Config.provider | Should -Be ''
        $r.Config.providerLocality | Should -Be ''
        @($r.Config.agent.Keys).Count | Should -Be 0
        (Test-SlopConfig -Config $r.Config).Ok | Should -BeTrue
    }

    It 'Set-SlopConfigBrain rejects a non-loopback custom endpoint' {
        $r = Set-SlopConfigBrain -Config (New-SlopDefaultConfig) -Brain 'custom' -Provider '' `
            -ProviderLocality '' -ProviderTier 'free' -EndpointUrl 'https://example.invalid/v1' `
            -Model 'local-model' -AgentId '' -CapabilityProfile 'companion'
        $r.Ok | Should -BeFalse
        ($r.Errors -join '; ') | Should -Match 'endpointUrl'
    }

    It 'Set-SlopConfigBrain requires a model for OpenCode and defaults the agent id' {
        $missing = Set-SlopConfigBrain -Config (New-SlopDefaultConfig) -Brain 'opencode' -Provider 'Probe' `
            -ProviderLocality 'local' -ProviderTier 'free' -EndpointUrl '' -Model '' `
            -AgentId '' -CapabilityProfile 'companion'
        $missing.Ok | Should -BeFalse
        ($missing.Errors -join '; ') | Should -Match 'opencode model is required'

        $valid = Set-SlopConfigBrain -Config (New-SlopDefaultConfig) -Brain 'opencode' -Provider 'Probe' `
            -ProviderLocality 'local' -ProviderTier 'free' -EndpointUrl '' -Model 'probe-model' `
            -AgentId '' -CapabilityProfile 'companion'
        $valid.Ok | Should -BeTrue
        $valid.Config.agentId | Should -Be 'sloppy'
        $valid.Config.model | Should -Be 'probe-model'
        @($valid.Config.agent.Keys).Count | Should -Be 0
    }

    It 'Set-SlopConfigBrain clears route fields for builtin and rejects unknown brains' {
        $configured = New-SlopDefaultConfig
        $configured.provider = 'Probe'
        $configured.providerLocality = 'remote'
        $configured.providerTier = 'paid'
        $configured.endpointUrl = 'http://127.0.0.1:1234'
        $configured.model = 'probe-model'
        $configured.modelName = 'probe-model'
        $r = Set-SlopConfigBrain -Config $configured -Brain 'builtin' -Provider '' `
            -ProviderLocality '' -ProviderTier 'free' -EndpointUrl '' -Model '' `
            -AgentId '' -CapabilityProfile 'companion'
        $r.Ok | Should -BeTrue
        $r.Config.provider | Should -Be ''
        $r.Config.providerLocality | Should -Be ''
        $r.Config.providerTier | Should -Be 'free'
        $r.Config.endpointUrl | Should -Be ''
        $r.Config.model | Should -Be ''
        $r.Config.modelName | Should -Be ''

        $bad = Set-SlopConfigBrain -Config (New-SlopDefaultConfig) -Brain 'telepathy' -Provider '' `
            -ProviderLocality '' -ProviderTier 'free' -EndpointUrl '' -Model '' `
            -AgentId '' -CapabilityProfile 'companion'
        $bad.Ok | Should -BeFalse
        ($bad.Errors -join '; ') | Should -Match 'brain'
    }

    It 'backs up existing persona text before overwriting it' {
        Write-SlopPersona -Text 'first persona' -PersonaPath $script:PersonaPath
        Write-SlopPersona -Text 'second persona' -PersonaPath $script:PersonaPath
        Get-Content -LiteralPath "$script:PersonaPath.bak" -Raw | Should -Be 'first persona'
        Get-Content -LiteralPath $script:PersonaPath -Raw | Should -Be 'second persona'
        $bytes = [IO.File]::ReadAllBytes($script:PersonaPath)
        $bytes[0] | Should -Not -Be 0xEF
    }

    It 'does not fall back to LOCALAPPDATA in production code' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Config.ps1') -Raw
        $src | Should -Not -Match 'Join-Path \$env:LOCALAPPDATA ''Sloppy'''
        $src | Should -Not -Match 'SLOP_TEST_APPDATA'
    }
}
