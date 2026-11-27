#requires -Version 7.6
Describe 'Slop.Route' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Provider.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCode.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Route.ps1')
    }

    It 'classifies the bundled default' {
        Resolve-SlopRouteKind -Config @{ brain = 'builtin' } | Should -Be 'local-bundled'
    }

    It 'classifies a custom local endpoint' {
        Resolve-SlopRouteKind -Config @{ brain = 'custom' } | Should -Be 'custom'
    }

    It 'classifies an OpenCode route with a local provider' {
        Resolve-SlopRouteKind -Config @{ brain='opencode'; providerLocality='local' } |
            Should -Be 'opencode-local'
    }

    It 'classifies an OpenCode route without a paid tier' {
        Resolve-SlopRouteKind -Config @{ brain='opencode'; providerLocality='remote' } |
            Should -Be 'opencode-remote'
        @(Get-SlopRouteCatalog).Keys | Should -Not -Contain 'opencode-paid'
    }

    It 'lets an agent model preference win over the config default' {
        Resolve-SlopEffectiveModel -Agent @{ model='kimi-k3' } -Config @{ model='beam-free' } |
            Should -Be 'kimi-k3'
    }

    It 'falls back to the config model when the agent has no preference' {
        Resolve-SlopEffectiveModel -Agent @{} -Config @{ model='beam-free' } | Should -Be 'beam-free'
    }

    It 'badges locality, provider and effective model - not the tier' {
        Get-SlopRouteBadge -Kind 'opencode-local' -Provider 'Ollama' -Model 'qwen3:8b' |
            Should -Be 'Local · Ollama · qwen3:8b'
        Get-SlopRouteBadge -Kind 'opencode-remote' -Provider 'OpenCode Go' -Model 'Qwen3.5-2B Q4_K_M' |
            Should -Be 'Remote · OpenCode Go · Qwen3.5-2B Q4_K_M'
    }

    It 'rejects an unknown route kind' {
        { Get-SlopRouteBadge -Kind 'magic' -Provider 'x' -Model 'y' } | Should -Throw
    }

    It 'passes DisableThinking as a bare switch without positional leakage' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Route.ps1') -Raw
        $src | Should -Not -Match '-DisableThinking\s+\$true'
        $src | Should -Match '(?m)-DisableThinking\s*$'
    }

    It 'marks only remote routes as requiring disclosure' {
        (Get-SlopRouteCatalog)['opencode-remote'].TermsRequired | Should -BeTrue
        (Get-SlopRouteCatalog)['local-bundled'].TermsRequired | Should -BeFalse
        (Get-SlopRouteCatalog)['custom'].TermsRequired | Should -BeFalse
    }

    It 'never persists a credential in controlled config' {
        $cfg = New-SlopControlledConfig -Profile 'companion' -AgentId 'sloppy' -Model 'beam-free'
        ($cfg | ConvertTo-Json -Depth 8 -Compress) | Should -Not -Match 'apiKey|password|token|secret'
    }

    It 'plans a custom route without starting the bundled model' {
        $plan = Get-SlopRoutePlan -Config @{
            brain='custom'; endpointUrl='http://127.0.0.1:11434/'; model='qwen3:8b'
        } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'
        $plan.Ok | Should -BeTrue
        $plan.Kind | Should -Be 'custom'
        $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
        $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:11434'
        $plan.RequiresDisclosure | Should -BeFalse
    }

    It 'resolves bundled runtime from the app root, not LOCALAPPDATA' {
        $repoRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-root-' + [guid]::NewGuid().ToString('N'))
        $emptyLocal = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-empty-' + [guid]::NewGuid().ToString('N'))
        $savedLocal = $env:LOCALAPPDATA
        try {
            New-Item -ItemType Directory -Path (Join-Path $repoRoot 'runtime\llama-b12676-bin-win-cpu-x64') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repoRoot 'runtime\models') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $repoRoot 'runtime\llama-b12676-bin-win-cpu-x64\llama-server.exe') -Value ('x' * 2048) -NoNewline
            Set-Content -LiteralPath (Join-Path $repoRoot 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf') -Value ('x' * 2048) -NoNewline
            $env:LOCALAPPDATA = $emptyLocal

            $plan = Get-SlopRoutePlan -Config @{ brain='builtin' } -UserText 'hello' `
                -ScriptRootPath (Join-Path $repoRoot 'src') -RepoRootPath $repoRoot
            $plan.Ok | Should -BeTrue
            $plan.LocalModelPaths.ServerExe | Should -Be (Join-Path $repoRoot 'runtime\llama-b12676-bin-win-cpu-x64\llama-server.exe')
            $plan.LocalModelPaths.ModelFile | Should -Be (Join-Path $repoRoot 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf')
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            if (Test-Path -LiteralPath $repoRoot) { Remove-Item -LiteralPath $repoRoot -Recurse -Force }
            if (Test-Path -LiteralPath $emptyLocal) { Remove-Item -LiteralPath $emptyLocal -Recurse -Force }
        }
    }

    It 'plans a local-bundled route with the Qwen contract when runtime files exist' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-rt-' + [guid]::NewGuid().ToString('N'))
        $savedLocal = $env:LOCALAPPDATA
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $paths = Get-SlopRuntimePaths -InstallRoot $root
            New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ServerExe) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ModelFile) -Force | Out-Null
            Set-Content -LiteralPath $paths.ServerExe -Value ('x' * 2048) -NoNewline
            Set-Content -LiteralPath $paths.ModelFile -Value ('x' * 2048) -NoNewline

            $plan = Get-SlopRoutePlan -Config @{
                brain='builtin'; localContextSize=16384; localModelName='Qwen3.5-2B Q4_K_M'
            } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath $root

            $plan.Ok | Should -BeTrue
            $plan.Kind | Should -Be 'builtin'
            $plan.RouteKind | Should -Be 'local-bundled'
            $plan.ReadyToSend | Should -BeFalse
            $plan.NeedsLocalModelStart | Should -BeTrue
            $plan.Badge | Should -Be 'Local · bundled · Qwen3.5-2B Q4_K_M'
            $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
            $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:18080'
            $plan.LocalModelContextSize | Should -Be 16384
            $plan.LocalModelPaths.MmprojFile | Should -Be ''
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'fails closed for local-bundled route when runtime files are missing' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-miss-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $plan = Get-SlopRoutePlan -Config @{ brain='builtin' } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath $root
            $plan.Ok | Should -BeFalse
            $plan.Reason | Should -Match 'missing|llama-server|model'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'keeps route planning independent of any tier field' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'opencode'
        $cfg.providerLocality = 'remote'
        $cfg.provider = 'opencode-go'
        $cfg.agentId = 'sloppy'
        $cfg.openCodeBaseUrl = 'http://127.0.0.1:28894'
        $cat = Get-SlopRouteCatalog
        $cat['opencode-remote'].TermsRequired | Should -BeTrue
        $cat['opencode-remote'].Locality | Should -Be 'Remote'
    }
}
