#requires -Version 7.6
Describe 'Slop.Provider' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Config.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Lifecycle.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Provider.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCode.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Route.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.Adapter.OpenAi.ps1')
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-provider-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'reports the adapter contract and every stream marker' {
        $contract = Get-SlopAdapterContract
        $contract.Version | Should -Be 1
        $contract.EntryPoint | Should -Be 'Invoke-SlopAdapter'
        foreach ($marker in @('__DONE__', '__CONNECTED__', '__WARN__', '__ERR__', '__TOK__', '__OC')) {
            $contract.MarkerContract | Should -Contain $marker
        }
    }

    It 'builds a streaming request body with and without a persona' {
        $with = New-SlopChatRequestBody -SystemPrompt 'Be kind' -UserText 'hello' | ConvertFrom-Json
        $with.stream | Should -BeTrue
        @($with.messages).Count | Should -Be 2
        $with.messages[0].role | Should -Be 'system'
        $without = New-SlopChatRequestBody -SystemPrompt '' -UserText 'hello' | ConvertFrom-Json
        @($without.messages).Count | Should -Be 1
        $without.messages[0].role | Should -Be 'user'
        { New-SlopChatRequestBody -SystemPrompt '' -UserText ('x' * 8001) } | Should -Throw
    }

    It 'includes audio attachment as OpenAI-compatible input_audio content part when enabled' {
        $audio = @{
            type = 'audio'
            path = 'C:\fake\clip.wav'
            name = 'clip.wav'
            mediaType = 'audio/wav'
            dataBase64 = 'QUJDRA=='
        }
        $body = New-SlopChatRequestBody -SystemPrompt '' -UserText 'transcribe this' -Attachments @($audio) | ConvertFrom-Json
        $msg = @($body.messages)[-1]
        $msg.role | Should -Be 'user'
        @($msg.content).Count | Should -Be 2
        $msg.content[0].type | Should -Be 'text'
        $msg.content[0].text | Should -Be 'transcribe this'
        $msg.content[1].type | Should -Be 'input_audio'
        $msg.content[1].input_audio.data | Should -Be 'QUJDRA=='
        $msg.content[1].input_audio.format | Should -Be 'wav'
    }

    It 'includes image attachment as OpenAI-compatible image_url content part when enabled' {
        $img = @{
            type = 'image'
            name = 'pic.png'
            mediaType = 'image/png'
            dataBase64 = 'iVBORw0KGgo='
        }
        $body = New-SlopChatRequestBody -SystemPrompt '' -UserText 'what is this?' -Attachments @($img) | ConvertFrom-Json
        $msg = @($body.messages)[-1]
        @($msg.content).Count | Should -Be 2
        $msg.content[1].type | Should -Be 'image_url'
        $msg.content[1].image_url.url | Should -Match '^data:image/png;base64,'
    }

    It 'rejects unsupported attachment type or oversized attachment payload' {
        { New-SlopChatRequestBody -SystemPrompt '' -UserText 'hi' -Attachments @(@{ type='video'; dataBase64='QQ=='; mediaType='video/mp4' }) } | Should -Throw
        $big = 'A' * 16000001
        { New-SlopChatRequestBody -SystemPrompt '' -UserText 'hi' -Attachments @(@{ type='audio'; dataBase64=$big; mediaType='audio/wav' }) } | Should -Throw
    }

    It 'plans a custom endpoint without calling the bundled model helpers' {
        $plan = Get-SlopStreamPlan -Config @{
            brain='custom'; endpointUrl='http://127.0.0.1:11434/'; model='qwen3:8b'
        } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'
        $plan.Ok | Should -BeTrue
        $plan.Kind | Should -Be 'custom'
        $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:11434'
        $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
    }

    It 'reports a missing bundled model as a plain-language failure' {
        $fakeRoot = Join-Path $script:TestRoot 'missing-runtime'
        $paths = Get-SlopRuntimePaths -InstallRoot $fakeRoot
        # Start-SlopLocalModel checks real paths; a fake root must fail closed.
        (Test-SlopLocalModelPaths -Paths $paths).Ok | Should -BeFalse
        (Test-SlopLocalModelPaths -Paths $paths).Reason | Should -Match 'missing'
    }

    It 'hands the bundled brain startup contract to the worker' {
        $routeSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Route.ps1') -Raw
        $routeSrc | Should -Match 'NeedsLocalModelStart=\(-not \[bool\]\$LocalModelProcess\)'
        $routeSrc | Should -Match 'LocalModelPaths=\$paths'
        $routeSrc | Should -Match 'LocalModelContextSize=\$contextSize'
        $routeSrc | Should -Match 'ReadyToSend=\[bool\]\$LocalModelProcess'
        $appSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
        $appSrc | Should -Match 'Start-SlopLocalModel -Paths \$Plan\.LocalModelPaths -ContextSize \(\[int\]\$Plan\.LocalModelContextSize\)'
    }

    It 'selects the OpenCode route from config, not from an environment escape hatch' {
        $savedPassword = $env:OPENCODE_PASSWORD
        $env:OPENCODE_PASSWORD = 'test-password'
        try {
        $plan = Get-SlopStreamPlan -Config @{
            brain='opencode'; providerLocality='local'
            provider='Ollama'; model='qwen3:8b'; capabilityProfile='companion'
            agentId='sloppy'; openCodeBaseUrl='http://127.0.0.1:28894'; serviceConfigPath=''
        } -UserText 'hello' -ObservedProviderEndpointUrl 'http://127.0.0.1:11434' `
            -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'
        $plan.Ok | Should -BeTrue
        $plan.Kind | Should -Be 'opencode-local'
        $plan.Badge | Should -Be 'Local · Ollama · qwen3:8b'
        $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenCode\.ps1$'
        $plan.RequiresDisclosure | Should -BeFalse
        }
        finally { $env:OPENCODE_PASSWORD = $savedPassword }
    }

    It 'reads two SSE deltas and ignores a terminal frame' {
        $body = @(
            'data: {"choices":[{"delta":{"content":"one"}}]}'
            ''
            'data: {"choices":[{"delta":{"content":"two"}}]}'
            ''
            'data: [DONE]'
        ) -join "`n"
        $queue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
        $reader = [IO.StringReader]::new($body)
        $stats = Read-SlopSseStream -Reader $reader -Queue $queue -Token ([Threading.CancellationToken]::None)
        $stats.Tokens | Should -Be 2
        $stats.Malformed | Should -Be 0
        $stats.Cancelled | Should -BeFalse
        $queue.ToArray() | Should -Be @('one', 'two')
    }

    It 'keeps a valid delta when a second frame is malformed' {
        $body = @(
            'data: {"choices":[{"delta":{"content":"ok"}}]}'
            ''
            'data: {broken'
        ) -join "`n"
        $queue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
        $stats = Read-SlopSseStream -Reader ([IO.StringReader]::new($body)) -Queue $queue -Token ([Threading.CancellationToken]::None)
        $stats.Malformed | Should -Be 1
        $queue.ToArray() | Should -Contain 'ok'
    }

    It 'unblocks a stalled reader immediately on a pre-cancelled token' {
        $queue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
        $reader = [IO.StringReader]::new('')
        $cts = [Threading.CancellationTokenSource]::new()
        $cts.Cancel()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $stats = Read-SlopSseStream -Reader $reader -Queue $queue -Token $cts.Token
        $sw.Stop()
        $stats.Cancelled | Should -BeTrue
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 2
    }

    It 'drives Invoke-SlopAdapter against a loopback SSE server' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $job = $null
        $client = $null
        try {
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
            $lifecycle = Join-Path $PSScriptRoot '../src/Slop.Lifecycle.ps1'
            $adapter = Join-Path $PSScriptRoot '../src/Slop.Adapter.OpenAi.ps1'
            $body = New-SlopChatRequestBody -SystemPrompt '' -UserText 'hello'

            $job = Start-ThreadJob -ScriptBlock {
                param($BaseUrl, $RequestBody, $Lifecycle, $Adapter)
                . $Lifecycle
                . $Adapter
                $q = [Collections.Concurrent.ConcurrentQueue[string]]::new()
                Invoke-SlopAdapter -BaseUrl $BaseUrl -RequestBody $RequestBody -LifecyclePath $Lifecycle `
                    -Queue $q -Token ([Threading.CancellationToken]::None) -TimeoutSeconds 10
                return @($q.ToArray())
            } -ArgumentList "http://127.0.0.1:$port", $body, $lifecycle, $adapter

            $accept = $listener.AcceptTcpClientAsync()
            if (-not $accept.Wait(10000)) { throw 'adapter did not connect within 10 seconds' }
            $client = $accept.Result
            $stream = $client.GetStream()
            $writer = [IO.StreamWriter]::new($stream, [Text.Encoding]::ASCII)
            $writer.NewLine = "`r`n"
            $writer.AutoFlush = $true
            $writer.WriteLine('HTTP/1.1 200 OK')
            $writer.WriteLine('Content-Type: text/event-stream')
            $writer.WriteLine('Connection: close')
            $writer.WriteLine('')
            $writer.WriteLine('data: {"choices":[{"delta":{"content":"alpha"}}]}')
            $writer.WriteLine('')
            $writer.WriteLine('data: {"choices":[{"delta":{"content":"beta"}}]}')
            $writer.WriteLine('')
            $writer.WriteLine('data: [DONE]')
            $writer.WriteLine('')

            $items = @(Wait-Job $job -Timeout 20 | Out-Null; Receive-Job $job)
            $items | Should -Contain '__CONNECTED__'
            $items | Should -Contain 'alpha'
            $items | Should -Contain 'beta'
            @($items | Where-Object { $_ -like '__ERR__*' }).Count | Should -Be 0
        }
        finally {
            if ($client) { $client.Dispose() }
            $listener.Stop()
            if ($job) { Remove-Job $job -Force }
        }
    }
}
