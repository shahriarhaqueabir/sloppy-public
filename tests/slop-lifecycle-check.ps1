# Headless checks for S.L.O.P. request lifecycle. No WPF; Pester-backed.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
$lifecycle = Join-Path $PSScriptRoot '../src/Slop.Lifecycle.ps1'
if (Test-Path $lifecycle) { . $lifecycle }

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}

$required = @(
    'New-SlopRequestState', 'Start-SlopRequest', 'Set-SlopRequestConnected',
    'Set-SlopRequestFirstToken', 'Set-SlopRequestToken', 'Set-SlopRequestCompleted',
    'Set-SlopRequestFailed', 'Set-SlopRequestFinalized', 'Test-SlopRequestGeneration',
    'Get-SlopRequestTiming', 'Read-SlopSseStream', 'Resolve-SlopStreamToken',
    'Format-SlopStreamFailure', 'Format-SlopEmptyResponse'
)
$missing = @($required | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missing.Count) { throw "missing lifecycle functions: $($missing -join ', ')" }

$t0 = [datetime]'2026-11-22T10:00:00Z'

# 1. new state is idle and ungenerated
$s = New-SlopRequestState
Assert-True ($s.Phase -eq 'idle' -and $s.Generation -eq 0) 'new request state starts idle at generation 0'

# 2. start records the initiation phase and bumps generation
Assert-True (Start-SlopRequest -State $s -Now $t0) 'first request starts'
Assert-True ($s.Phase -eq 'initiated' -and $s.Generation -eq 1 -and $s.StartedAt -eq $t0) `
    'initiation records phase, generation and start time'

# 3. a second start while active is rejected and does not bump generation
Assert-True (-not (Start-SlopRequest -State $s -Now $t0.AddSeconds(1))) 'overlapping request is rejected'
Assert-True ($s.Generation -eq 1 -and $s.Phase -eq 'initiated') 'rejected start leaves state untouched'

# 4. connection established
Assert-True (Set-SlopRequestConnected -State $s -Generation 1 -Now $t0.AddSeconds(1)) 'connect succeeds'
Assert-True ($s.Phase -eq 'connected' -and $s.ConnectedAt -eq $t0.AddSeconds(1)) `
    'connected records header receipt time'

# 5. first token records TTFT separately from later gaps
Assert-True (Set-SlopRequestFirstToken -State $s -Generation 1 -Now $t0.AddSeconds(2.5)) 'first token accepted'
$timing = Get-SlopRequestTiming -State $s -Now $t0.AddSeconds(2.5)
Assert-True ([Math]::Abs($timing.Ttft - 2.5) -lt 0.001 -and $null -eq $timing.InterTokenGap) `
    "TTFT measured, no inter-token gap yet (ttft=$($timing.Ttft))"
Assert-True ($s.Phase -eq 'streaming') 'first token moves phase to streaming'

# 6. inter-token gap is tracked without overwriting TTFT
Assert-True (Set-SlopRequestToken -State $s -Generation 1 -Now $t0.AddSeconds(6.0)) 'later token accepted'
$timing = Get-SlopRequestTiming -State $s -Now $t0.AddSeconds(6.0)
Assert-True ([Math]::Abs($timing.Ttft - 2.5) -lt 0.001 -and [Math]::Abs($timing.InterTokenGap - 3.5) -lt 0.001) `
    "inter-token gap measured independently of TTFT (gap=$($timing.InterTokenGap))"

# 7. stale generation cannot mutate state
Assert-True (-not (Set-SlopRequestCompleted -State $s -Generation 0 -Now $t0.AddSeconds(7))) `
    'stale completion is ignored'
Assert-True (-not (Test-SlopRequestGeneration -State $s -Generation 0)) 'stale generation fails guard'
Assert-True (Test-SlopRequestGeneration -State $s -Generation 1) 'current generation passes guard'

# 8. completion and finalization are separate phases
Assert-True (Set-SlopRequestCompleted -State $s -Generation 1 -Now $t0.AddSeconds(7)) 'completion accepted'
Assert-True ($s.Phase -eq 'completed' -and $s.CompletedAt -eq $t0.AddSeconds(7)) 'completion recorded'
Assert-True (-not (Test-SlopRequestGeneration -State $s -Generation 1)) 'completed request is no longer current'
Assert-True (Set-SlopRequestFinalized -State $s -Generation 1 -Now $t0.AddSeconds(7.1)) 'finalization accepted'
Assert-True ($s.Phase -eq 'finalized' -and $s.FinalizedAt -eq $t0.AddSeconds(7.1)) 'finalization recorded'

# 9. a new request can start after finalization
Assert-True (Start-SlopRequest -State $s -Now $t0.AddSeconds(8)) 'next request starts cleanly'
Assert-True ($s.Generation -eq 2 -and $s.Phase -eq 'initiated') 'generation advances for reused state'

# 10. failure records its reason
Assert-True (Set-SlopRequestFailed -State $s -Generation 2 -Reason 'HTTP 500' -Now $t0.AddSeconds(9)) 'failure accepted'
Assert-True ($s.Phase -eq 'failed' -and $s.FailureReason -eq 'HTTP 500') 'failure reason recorded'

# 11. SSE reader parses deltas, ignores noise and counts malformed events
$queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$sse = @(
    ': keepalive',
    'data: {"choices":[{"delta":{"content":"Hel"}}]}',
    '',
    'data: {"choices":[{"delta":{"content":"lo"}}]}',
    'event: ping',
    'data: {not json}',
    'data: {"choices":[{"delta":{"content":" world"}}]}',
    'data: [DONE]',
    'data: {"choices":[{"delta":{"content":"IGNORED"}}]}'
) -join "`n"
$stats = Read-SlopSseStream -Reader ([System.IO.StringReader]::new($sse)) -Queue $queue
$tokens = @(); $tok = $null; while ($queue.TryDequeue([ref]$tok)) { $tokens += $tok }
Assert-True (($tokens -join '') -eq 'Hello world') 'SSE reader concatenates deltas only'
Assert-True ($stats.Malformed -eq 1 -and $stats.Tokens -eq 3) `
    "SSE reader counts malformed events and tokens (bad=$($stats.Malformed), tokens=$($stats.Tokens))"

# 12. stream token classification
$d = Resolve-SlopStreamToken -Token '__DONE__'
Assert-True ($d.Kind -eq 'done') 'DONE classified'
$c = Resolve-SlopStreamToken -Token '__ERR__Cancelled'
$to = Resolve-SlopStreamToken -Token '__ERR__Timeout'
$h = Resolve-SlopStreamToken -Token '__ERR__HTTP 503'
$e = Resolve-SlopStreamToken -Token '__ERR__boom'
$n = Resolve-SlopStreamToken -Token 'ordinary text'
$tk = Resolve-SlopStreamToken -Token '__TOK__Hello from OpenCode'
Assert-True ($c.Kind -eq 'cancelled' -and $to.Kind -eq 'timeout' -and $h.Kind -eq 'http' -and $e.Kind -eq 'error' -and $n.Kind -eq 'token') `
    'error reasons classified distinctly from plain tokens'
Assert-True ($tk.Kind -eq 'token' -and $tk.Text -ceq 'Hello from OpenCode') `
    'bridge __TOK__ marker is stripped before display'

# 13. failure formatting preserves partial text and labels each path
$partial = "half answer`nsecond line"
$cf = Format-SlopStreamFailure -PartialText $partial -Kind $c.Kind -Reason $c.Reason
Assert-True ($cf.StartsWith($partial) -and $cf.Contains('[cancelled]')) 'cancellation preserves partial text'
$tf = Format-SlopStreamFailure -PartialText $partial -Kind $to.Kind -Reason $to.Reason
Assert-True ($tf.Contains('[timeout')) 'timeout is labelled as timeout, not cancellation'
$hf = Format-SlopStreamFailure -PartialText $partial -Kind $h.Kind -Reason $h.Reason
Assert-True ($hf.Contains('HTTP 503')) 'HTTP error keeps status code'
$ef = Format-SlopStreamFailure -PartialText '' -Kind $e.Kind -Reason $e.Reason
Assert-True ($ef -eq '[error: boom]') 'empty partial still produces an error label'

# 14. empty response is explicit
Assert-True ((Format-SlopEmptyResponse -Text '   ') -eq '[empty response]') 'whitespace-only response labelled empty'
Assert-True ($null -eq (Format-SlopEmptyResponse -Text 'real answer')) 'non-empty response needs no label'

# 15. connection and warning markers are classified
$co = Resolve-SlopStreamToken -Token '__CONNECTED__'
$wa = Resolve-SlopStreamToken -Token '__WARN__3 malformed event(s)'
Assert-True ($co.Kind -eq 'connected' -and $wa.Kind -eq 'warning') `
    'connection and warning markers classified'
Assert-True ($wa.Reason -eq '3 malformed event(s)') 'warning reason preserved'

# 16. SSE reader honours a cancellation token — Stop must reach the blocking reader.
# Graceful degradation keeps RED readable when the -Token parameter does not exist yet.
$cancelCts = [System.Threading.CancellationTokenSource]::new()
$cancelCts.Cancel()
$cancelQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$longSse = (1..500 | ForEach-Object { 'data: {"choices":[{"delta":{"content":"x"}}]}' }) -join "`n"
$readerParams = @{ Reader = [System.IO.StringReader]::new($longSse); Queue = $cancelQueue }
if ((Get-Command Read-SlopSseStream).Parameters.ContainsKey('Token')) {
    $readerParams.Token = $cancelCts.Token
}
$cancelSw = [System.Diagnostics.Stopwatch]::StartNew()
$cancelStats = Read-SlopSseStream @readerParams
$cancelSw.Stop()
Assert-True ($cancelStats.Cancelled -eq $true) 'pre-cancelled SSE reader reports cancellation'
Assert-True ($cancelSw.Elapsed.TotalSeconds -lt 1) `
    "cancelled SSE reader returns promptly ($([Math]::Round($cancelSw.Elapsed.TotalSeconds,2))s)"
$extra = $null; $emitted = 0
while ($cancelQueue.TryDequeue([ref]$extra)) { $emitted++ }
Assert-True ($emitted -eq 0) "cancelled SSE reader emits no tokens (emitted=$emitted)"

# 17. a stalled reader unblocks on cancellation (ReadLine must not hang Stop).
# The fake blocks in Read() until either its gate is released or it is disposed;
# it self-cancels after 150 ms so the test is deterministic without extra threads.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public class SlopBlockingReader : TextReader {
    private ManualResetEventSlim gate = new ManualResetEventSlim(false);
    private Timer watchdog;
    public CancellationTokenSource Cts = new CancellationTokenSource();
    public SlopBlockingReader() {
        watchdog = new Timer(_ => gate.Set(), null, 2000, Timeout.Infinite);
    }
    public void Release() { gate.Set(); }
    protected override void Dispose(bool disposing) {
        gate.Set();
        if (watchdog != null) { watchdog.Dispose(); }
        base.Dispose(disposing);
    }
    public override int Read() {
        Cts.CancelAfter(150);
        gate.Wait();
        return -1;
    }
    public override int Read(char[] buffer, int index, int count) {
        Cts.CancelAfter(150);
        gate.Wait();
        return 0;
    }
    public override int Peek() {
        Cts.CancelAfter(150);
        gate.Wait();
        return -1;
    }
    public override System.Threading.Tasks.ValueTask<string> ReadLineAsync(
        System.Threading.CancellationToken ct) {
        Cts.CancelAfter(150);
        ct.Register(() => gate.Set());
        return new System.Threading.Tasks.ValueTask<string>(
            System.Threading.Tasks.Task.Run(() => { gate.Wait(); return (string)null; }));
    }
}
'@
$stallReader = [SlopBlockingReader]::new()
$stallQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$stallSw = [System.Diagnostics.Stopwatch]::StartNew()
$stallStats = Read-SlopSseStream -Reader $stallReader -Queue $stallQueue -Token $stallReader.Cts.Token
$stallSw.Stop()
Assert-True ($stallStats.Cancelled -eq $true) 'stalled SSE reader reports cancellation while blocked'
Assert-True ($stallSw.Elapsed.TotalSeconds -lt 2) `
    "stalled SSE reader unblocks promptly on cancel ($([Math]::Round($stallSw.Elapsed.TotalSeconds,2))s)"
$stallReader.Release()
$stallReader.Cts.Dispose()

# 17. hidden reasoning becomes an explicit fallback only when no visible answer exists
$hasThinkingFallback = (Get-Command Format-SlopThinkingFallback -ErrorAction SilentlyContinue) -ne $null
Assert-True $hasThinkingFallback 'thinking fallback formatter exists'
if ($hasThinkingFallback) {
    $fb = Format-SlopThinkingFallback -Thinking '  hidden answer  ' -VisibleText ''
    Assert-True ($fb -eq '[thinking] hidden answer') 'reasoning becomes labelled fallback text'
    Assert-True ($null -eq (Format-SlopThinkingFallback -Thinking 'x' -VisibleText 'visible')) `
        'visible text is never replaced by thinking'
}

$thinkQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$thinkSse = @(
    'data: {"choices":[{"delta":{"content":""}}]}',
    'data: {"choices":[{"delta":{"reasoning_content":"hel"}}]}',
    'data: {"choices":[{"delta":{"reasoning_content":"lo"}}]}',
    'data: [DONE]'
) -join "`n"
$thinkStats = Read-SlopSseStream -Reader ([System.IO.StringReader]::new($thinkSse)) -Queue $thinkQueue
$thinkTokens = @(); $thinkTok = $null
while ($thinkQueue.TryDequeue([ref]$thinkTok)) { $thinkTokens += $thinkTok }
Assert-True ($thinkStats.Tokens -eq 0 -and $thinkStats.Thinking -eq 'hello') `
    'SSE reader accumulates reasoning_content separately from visible tokens'
Assert-True ($thinkTokens.Count -eq 1 -and $thinkTokens[0] -eq '__THINK__hello') `
    'a reasoning-only stream emits exactly one __THINK__ control token'

$bothQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$bothSse = @(
    'data: {"choices":[{"delta":{"content":"shown","reasoning_content":"hidden"}}]}',
    'data: [DONE]'
) -join "`n"
$bothStats = Read-SlopSseStream -Reader ([System.IO.StringReader]::new($bothSse)) -Queue $bothQueue
$bothTokens = @(); $bothTok = $null
while ($bothQueue.TryDequeue([ref]$bothTok)) { $bothTokens += $bothTok }
Assert-True (($bothTokens -join '') -eq 'shown') `
    'a stream with visible content never emits __THINK__'
Assert-True ((Resolve-SlopStreamToken -Token '__THINK__hello').Kind -eq 'thinking') `
    '__THINK__ is classified as a distinct lifecycle kind'

Describe 'Slop request lifecycle' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
