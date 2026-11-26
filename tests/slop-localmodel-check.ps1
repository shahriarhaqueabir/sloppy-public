#requires -Version 7.6
Describe 'Slop.LocalModel' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1')
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-model-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'resolves Qwen runtime paths under a supplied install root' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $paths.InstallRoot | Should -Be $script:TestRoot
        $paths.ServerExe | Should -Match 'runtime\\llama-b12676-bin-win-cuda-13\.5-x64\\llama-server\.exe$'
        $paths.ModelFile | Should -Match 'models\\Qwen3\.5-2B-Q4_K_M\.gguf$'
        $paths.MmprojFile | Should -Be ''
        $paths.Port | Should -Be 18080
        $paths.BaseUrl | Should -Be 'http://127.0.0.1:18080'
    }

    It 'uses configured local model/mmproj file names when provided' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot -ModelFile 'models\custom.gguf' -MmprojFile 'models\custom-mmproj.gguf'
        $paths.ModelFile | Should -Be (Join-Path $script:TestRoot 'models\custom.gguf')
        $paths.MmprojFile | Should -Be (Join-Path $script:TestRoot 'models\custom-mmproj.gguf')
    }

    It 'requires server and model, treats empty mmproj as optional, and checks a configured mmproj' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $r = Test-SlopLocalModelPaths -Paths $paths
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'llama-server'
        $r.Reason | Should -Match 'model file'
        $r.Reason | Should -Not -Match 'mmproj'

        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ServerExe) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ModelFile) -Force | Out-Null
        Set-Content -LiteralPath $paths.ServerExe -Value ('x' * 2048) -NoNewline
        Set-Content -LiteralPath $paths.ModelFile -Value ('x' * 2048) -NoNewline
        $r2 = Test-SlopLocalModelPaths -Paths $paths
        $r2.Ok | Should -BeTrue

        $paths.MmprojFile = Join-Path $script:TestRoot 'models\missing-mmproj.gguf'
        $r3 = Test-SlopLocalModelPaths -Paths $paths
        $r3.Ok | Should -BeFalse
        $r3.Reason | Should -Match 'mmproj'

        $paths.Port = 80
        $r4 = Test-SlopLocalModelPaths -Paths $paths
        $r4.Ok | Should -BeFalse
        $r4.Reason | Should -Match 'port'
    }

    It 'builds llama arguments with --jinja, no default mmproj, allowed context size, and clamped threads' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $llamaArgs = @(New-SlopLlamaArguments -Paths $paths -Threads 99 -ContextSize 16384)
        $llamaArgs | Should -Contain '--model'
        $llamaArgs | Should -Contain $paths.ModelFile
        $llamaArgs | Should -Not -Contain '--mmproj'
        $llamaArgs | Should -Contain '--jinja'
        $llamaArgs | Should -Contain '--ctx-size'
        $llamaArgs | Should -Contain '16384'
        $llamaArgs | Should -Contain '--cache-ram'
        $llamaArgs | Should -Contain '0'
        $llamaArgs | Should -Contain '--host'
        $llamaArgs | Should -Contain '127.0.0.1'
        $llamaArgs | Should -Contain '--port'
        $llamaArgs | Should -Contain '18080'
        $llamaArgs | Should -Contain '--alias'
        $llamaArgs | Should -Contain 'sloppy'
        $idx = [array]::IndexOf($llamaArgs, '--threads')
        [int]$llamaArgs[$idx + 1] | Should -BeLessOrEqual 8
        [int]$llamaArgs[$idx + 1] | Should -BeGreaterOrEqual 2
    }

    It 'adds --mmproj only when a projector path is configured' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot -MmprojFile 'models\custom-mmproj.gguf'
        $llamaArgs = @(New-SlopLlamaArguments -Paths $paths)
        $llamaArgs | Should -Contain '--mmproj'
        $llamaArgs | Should -Contain $paths.MmprojFile
        $llamaArgs | Should -Contain '--jinja'
    }

    It 'falls back to default context size for invalid values' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $args = @(New-SlopLlamaArguments -Paths $paths -ContextSize 99999)
        $idx = [array]::IndexOf($args, '--ctx-size')
        $args[$idx + 1] | Should -Be '8192'
    }

    It 'accepts all allowed context sizes and exposes the contract' {
        @(Get-SlopAllowedContextSizes) | Should -Be @(8192, 16384, 32768)
        foreach ($size in 8192,16384,32768) {
            Resolve-SlopLocalContextSize -ContextSize $size | Should -Be $size
            $args = @(New-SlopLlamaArguments -Paths (Get-SlopRuntimePaths -InstallRoot $script:TestRoot) -ContextSize $size)
            $idx = [array]::IndexOf($args, '--ctx-size')
            $args[$idx + 1] | Should -Be ([string]$size)
        }
    }

    It 'passes context size through Start-SlopLocalModel argument construction' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ServerExe) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.ModelFile) -Force | Out-Null
        Set-Content -LiteralPath $paths.ServerExe -Value ('x' * 2048) -NoNewline
        Set-Content -LiteralPath $paths.ModelFile -Value ('x' * 2048) -NoNewline
        # We cannot start a real llama-server in unit tests; assert the contract
        # by checking Start-SlopLocalModel accepts ContextSize and builds args with it.
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.LocalModel.ps1') -Raw
        $src | Should -Match 'function Start-SlopLocalModel\s*\{[\s\S]*?\[int\]\$ContextSize'
        $src | Should -Match 'New-SlopLlamaArguments\s+-Paths\s+\$Paths\s+-ContextSize\s+\$ContextSize'
    }

    It 'detects a held loopback port and frees it afterwards' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
            Test-SlopPortAvailable -Port $port | Should -BeFalse
        }
        finally { $listener.Stop() }
        Test-SlopPortAvailable -Port $port | Should -BeTrue
    }

    It 'returns a non-throwing failure for an unused local port' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
        }
        finally { $listener.Stop() }
        $r = Test-SlopLocalModelHealth -BaseUrl "http://127.0.0.1:$port" -TimeoutMs 300
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Not -BeNullOrEmpty
    }

    It 'gives memory-specific copy for an OOM reason and the tray hint otherwise' {
        Format-SlopLocalModelFailure -Reason 'out of memory' | Should -Match 'not enough free memory'
        Format-SlopLocalModelFailure -Reason 'missing binary' | Should -Match 'change brains any time'
    }

    It 'treats a null or exited process as a no-op on stop' {
        $child = $null
        try {
            { Stop-SlopLocalModel -Process $null } | Should -Not -Throw
            $child = Start-Process -FilePath 'pwsh' -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru
            Start-Sleep -Milliseconds 300
            $child.Refresh()
            if (-not $child.HasExited) {
                Stop-Process -Id $child.Id -Force
                $child.WaitForExit()
            }
            { Stop-SlopLocalModel -Process $child } | Should -Not -Throw
        }
        finally {
            if ($child -and -not $child.HasExited) { Stop-Process -Id $child.Id -Force }
        }
    }

    It 'defaults runtime paths to the canonical app root' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:TestRoot
            $paths = Get-SlopRuntimePaths
            $paths.InstallRoot | Should -Be ([IO.Path]::GetFullPath($script:TestRoot))
            $paths.ModelFile | Should -Be (Join-Path ([IO.Path]::GetFullPath($script:TestRoot)) 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf')
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }
}
