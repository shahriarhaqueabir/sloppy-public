# tests/slop-tour-check.ps1
# Guards the architecture tour's file/line anchors against source drift.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}

$root = Join-Path $PSScriptRoot '..'
$tourPath = Join-Path $root '.tours/architect-slop-architecture.tour'
Assert-True (Test-Path $tourPath) 'architecture tour file exists'
if (Test-Path $tourPath) {
    $tour = Get-Content $tourPath -Raw | ConvertFrom-Json
    Assert-True ($tour.steps.Count -eq 18) 'tour has 18 steps'

    # Expected text at each anchored line. A stale anchor usually lands on a
    # blank line or a brace; these fragments make that fail loudly.
    $expected = @{
        1  = 'Status: accepted'
        3  = 'Add-Type -AssemblyName PresentationFramework'
        4  = 'function New-SlopMotionState'
        5  = 'function Get-SlopIdleAction'
        6  = 'public sealed class SlopFrame'
        7  = 'void Build()'
        8  = 'function New-SlopFaceLayer'
        9  = 'function New-SlopRequestState'
        10 = 'function Test-SlopOpenCodeConfig'
        11 = 'function Start-Stream'
        12 = 'function Add-SlopApprovalCard'
        13 = 'function Request-StopStream'
        14 = 'function Invoke-SlopSenseScan'
        15 = 'function Expand-Chat'
        16 = 'MotionTimer'
        17 = 'function Apply-SlopMotion'
    }

    $i = 0
    foreach ($step in $tour.steps) {
        $i++
        if ($step.directory) {
            Assert-True (Test-Path (Join-Path $root $step.directory)) "step $i directory exists: $($step.directory)"
            continue
        }
        if (-not $step.file) { continue } # closing 'Next Steps' step has no anchor

        $path = Join-Path $root $step.file
        if (-not (Test-Path $path)) {
            Assert-True $false "step $i file exists: $($step.file)"
            continue
        }
        $lines = @(Get-Content $path)
        $n = [int]$step.line
        $inRange = ($n -ge 1 -and $n -le $lines.Count)
        Assert-True $inRange "step $i line in range ($($step.file):$n of $($lines.Count))"
        if (-not $inRange) { continue }

        $text = $lines[$n - 1].Trim()
        $want = $expected[$i]
        if ($want) {
            Assert-True ($text -match [regex]::Escape($want)) "step $i anchors '$want' ($($step.file):$n :: $text)"
        } else {
            Assert-True ($text -notin @('', '{', '}')) "step $i anchor is substantive ($($step.file):$n :: $text)"
        }
    }

    # Doc-drift claims that were corrected alongside the anchors.
    Assert-True ($tour.steps[1].description -notmatch 'pure math/state') 'module map no longer calls the impure modules pure'
    Assert-True ($tour.steps[5].title -match '48-point' -and $tour.steps[5].description -match 'N=48') 'membrane step states the current N=48 ring'
    Assert-True ($tour.steps[6].description -match 'not used at runtime') 'silhouette data is not claimed as a runtime anchor'
    Assert-True ($tour.steps[14].description -match 'full chat height' -and $tour.steps[14].description -match 'hide chat' -and $tour.steps[14].description -match 'exact pane height') 'window step describes the full-height deck contract'

    $uiFacing = @(
        'src/Slop.ps1', 'src/Slop.ChatWindow.ps1', 'src/Slop.Onboarding.ps1',
        'docs/architecture.md', 'docs/brand-audit.md'
    )
    $sensitive = 'providerID|modelID|x-opencode-org-id|orgId|Authorization|OPENCODE_PASSWORD|C:\\Users\\'
    foreach ($relative in $uiFacing) {
        $path = Join-Path $root $relative
        if (-not (Test-Path $path)) { continue }
        $text = Get-Content $path -Raw
        Assert-True ($text -notmatch $sensitive) "no raw catalog, header, credential or user-path detail in $relative"
    }
}

Describe 'Slop architecture tour anchors' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
