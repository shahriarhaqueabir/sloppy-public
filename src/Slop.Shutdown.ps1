# Pure shutdown phrase and confirmation state. No WPF, no process calls.
$ErrorActionPreference = 'Stop'

function Get-SlopShutdownPrompt {
    return 'Are you sure? Say or type yes.'
}

function Test-SlopShutdownPhrase {
    param([AllowEmptyString()][string]$Text)
    $normalized = ([string]$Text).ToLowerInvariant() -replace '[^a-z]', ' '
    return ($normalized -match '\bsloppy\s+shutdown\b')
}

function New-SlopShutdownConfirmation {
    return [pscustomobject]@{ Pending = $false }
}

function Get-SlopShutdownTeardownSteps {
    return @(
        'StopTimers'
        'CancelStream'
        'RejectPendingApprovals'
        'DeleteOpenCodeSession'
        'CloseChat'
        'ShutdownApplication'
    )
}

function Resolve-SlopShutdownInput {
    param(
        [Parameter(Mandatory)]$State,
        [AllowEmptyString()][string]$Text
    )
    $value = ([string]$Text).Trim().ToLowerInvariant()
    if (-not $State.Pending) {
        if (Test-SlopShutdownPhrase -Text $Text) {
            return [pscustomobject]@{
                ConfirmationRequired = $true
                ShouldShutdown = $false
                Cancelled = $false
                TextForNormalHandling = ''
                State = [pscustomobject]@{ Pending = $true }
            }
        }
        return [pscustomobject]@{
            ConfirmationRequired = $false
            ShouldShutdown = $false
            Cancelled = $false
            TextForNormalHandling = $Text
            State = $State
        }
    }
    if ($value -in @('yes','y','confirm')) {
        return [pscustomobject]@{
            ConfirmationRequired = $false
            ShouldShutdown = $true
            Cancelled = $false
            TextForNormalHandling = ''
            State = [pscustomobject]@{ Pending = $false }
        }
    }
    return [pscustomobject]@{
        ConfirmationRequired = $false
        ShouldShutdown = $false
        Cancelled = $true
        TextForNormalHandling = $Text
        State = [pscustomobject]@{ Pending = $false }
    }
}
