# S.L.O.P. request lifecycle: pure state, parsing and formatting. No WPF, no backend.
$ErrorActionPreference = 'Stop'

$SlopActivePhases = @('initiated', 'connected', 'streaming')

function New-SlopRequestState {
    return @{
        Generation        = 0
        Phase             = 'idle'
        StartedAt         = $null
        ConnectedAt       = $null
        FirstTokenAt      = $null
        LastTokenAt       = $null
        PreviousTokenAt   = $null
        CompletedAt       = $null
        FinalizedAt       = $null
        FailureReason     = $null
        MalformedCount    = 0
        TokenCount        = 0
        LastInterTokenGap = $null
    }
}

function Test-SlopRequestGeneration {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation
    )
    return ($State.Generation -eq $Generation -and $State.Phase -in $SlopActivePhases)
}

function Start-SlopRequest {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if ($State.Phase -in $SlopActivePhases) { return $false }
    $State.Generation++
    $State.Phase = 'initiated'
    $State.StartedAt = $Now
    $State.ConnectedAt = $null
    $State.FirstTokenAt = $null
    $State.LastTokenAt = $null
    $State.PreviousTokenAt = $null
    $State.CompletedAt = $null
    $State.FinalizedAt = $null
    $State.FailureReason = $null
    $State.MalformedCount = 0
    $State.TokenCount = 0
    $State.LastInterTokenGap = $null
    return $true
}

function Set-SlopRequestConnected {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'connected'
    $State.ConnectedAt = $Now
    return $true
}

function Set-SlopRequestFirstToken {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'streaming'
    $State.FirstTokenAt = $Now
    $State.LastTokenAt = $Now
    $State.PreviousTokenAt = $null
    $State.TokenCount = 1
    $State.LastInterTokenGap = $null
    return $true
}

function Set-SlopRequestToken {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    if ($null -eq $State.FirstTokenAt) {
        return Set-SlopRequestFirstToken -State $State -Generation $Generation -Now $Now
    }
    $State.PreviousTokenAt = $State.LastTokenAt
    $State.LastTokenAt = $Now
    if ($null -ne $State.PreviousTokenAt) {
        $State.LastInterTokenGap = ($Now - $State.PreviousTokenAt).TotalSeconds
    }
    $State.TokenCount++
    return $true
}

function Set-SlopRequestCompleted {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'completed'
    $State.CompletedAt = $Now
    return $true
}

function Set-SlopRequestFailed {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [Parameter(Mandatory)][string]$Reason,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if (-not (Test-SlopRequestGeneration -State $State -Generation $Generation)) { return $false }
    $State.Phase = 'failed'
    $State.FailureReason = $Reason
    return $true
}

function Set-SlopRequestFinalized {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][int]$Generation,
        [datetime]$Now = [DateTime]::UtcNow
    )
    if ($State.Generation -ne $Generation) { return $false }
    $State.Phase = 'finalized'
    $State.FinalizedAt = $Now
    return $true
}

function Get-SlopRequestTiming {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = [DateTime]::UtcNow
    )
    $ttft = $null
    if ($null -ne $State.FirstTokenAt -and $null -ne $State.StartedAt) {
        $ttft = ($State.FirstTokenAt - $State.StartedAt).TotalSeconds
    }
    $since = $null
    if ($null -ne $State.LastTokenAt) { $since = ($Now - $State.LastTokenAt).TotalSeconds }
    $elapsed = $null
    if ($null -ne $State.StartedAt) { $elapsed = ($Now - $State.StartedAt).TotalSeconds }
    return @{
        Ttft           = $ttft
        InterTokenGap  = $State.LastInterTokenGap
        SinceLastToken = $since
        Elapsed        = $elapsed
    }
}

function Read-SlopSseStream {
    param(
        [Parameter(Mandatory)][System.IO.TextReader]$Reader,
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentQueue[string]]$Queue,
        [System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None
    )
    $malformed = 0
    $tokens = 0
    $thinking = ''
    while ($true) {
        if ($Token.IsCancellationRequested) {
            return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
        }
        try {
            $line = $Reader.ReadLineAsync($Token).GetAwaiter().GetResult()
        }
        catch [System.OperationCanceledException] {
            return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
        }
        catch [System.ObjectDisposedException] {
            if ($Token.IsCancellationRequested) {
                return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
            }
            throw
        }
        if ($null -eq $line) {
            if ($Token.IsCancellationRequested) {
                return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
            }
            break
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:')) { continue }
        $data = $line.Substring(5).Trim()
        if ($data -eq '[DONE]') { break }
        try {
            $obj = $data | ConvertFrom-Json -ErrorAction Stop
            $delta = $obj.choices[0].delta.content
            if ($delta) {
                $Queue.Enqueue([string]$delta)
                $tokens++
            }
            $reasoning = $obj.choices[0].delta.reasoning_content
            if ($reasoning) { $thinking += [string]$reasoning }
        } catch {
            $malformed++
        }
    }
    # Only surface thinking when the model produced no visible answer. A real
    # answer must never be replaced or prefixed by its hidden reasoning.
    if ($tokens -eq 0 -and -not [string]::IsNullOrWhiteSpace($thinking)) {
        $Queue.Enqueue('__THINK__' + $thinking)
    }
    return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $false; Thinking = $thinking }
}

function Resolve-SlopStreamToken {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Token)
    if ($Token -eq '__DONE__') { return @{ Kind = 'done'; Reason = $null; Text = $null } }
    if ($Token -eq '__CONNECTED__') { return @{ Kind = 'connected'; Reason = $null; Text = $null } }
    if ($Token.StartsWith('__WARN__')) {
        return @{ Kind = 'warning'; Reason = $Token.Substring(8); Text = $null }
    }
    if ($Token.StartsWith('__ERR__')) {
        $reason = $Token.Substring(7)
        $kind = if ($reason -eq 'Cancelled') { 'cancelled' }
                elseif ($reason -like 'Timeout*') { 'timeout' }
                elseif ($reason -like 'HTTP *') { 'http' }
                else { 'error' }
        return @{ Kind = $kind; Reason = $reason; Text = $null }
    }
    if ($Token.StartsWith('__THINK__')) {
        return @{ Kind = 'thinking'; Reason = $null; Text = $Token.Substring(9) }
    }
    # The OpenCode bridge marks its deltas so they cannot be confused with the
    # lifecycle control tokens above; strip the marker before rendering.
    if ($Token.StartsWith('__TOK__')) {
        return @{ Kind = 'token'; Reason = $null; Text = $Token.Substring(7) }
    }
    return @{ Kind = 'token'; Reason = $null; Text = $Token }
}

function Format-SlopStreamFailure {
    param(
        [string]$PartialText,
        [Parameter(Mandatory)][ValidateSet('cancelled', 'timeout', 'http', 'error')][string]$Kind,
        [string]$Reason
    )
    $label = switch ($Kind) {
        'cancelled' { '[cancelled]' }
        'timeout' {
            $secs = 300
            if ($Reason -match 'Timeout\s+(\d+)') { $secs = [int]$Matches[1] }
            "[timeout after ${secs}s]"
        }
        'http' { "[error: $Reason]" }
        'error' { "[error: $Reason]" }
    }
    if ([string]::IsNullOrWhiteSpace($PartialText)) { return $label }
    return $PartialText.TrimEnd() + "`n" + $label
}

function Format-SlopEmptyResponse {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '[empty response]' }
    return $null
}

function Format-SlopThinkingFallback {
    param([string]$Thinking, [string]$VisibleText)
    if (-not [string]::IsNullOrWhiteSpace($VisibleText)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Thinking)) { return $null }
    return '[thinking] ' + $Thinking.Trim()
}
