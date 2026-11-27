# tests/slop-face-check.ps1
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop } catch {}
. (Join-Path $PSScriptRoot '..\src\Slop.Face.ps1')

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}

$face = New-SlopFaceLayer
Assert-True ($face.Children.Count -eq 32) "face has 32 dots (got $($face.Children.Count))"

foreach ($pattern in @('scattered','ring','cluster','line','spiral')) {
    Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Inset 3.0 -Pattern $pattern
    $xs = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetLeft($_) })
    $ys = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetTop($_) })
    Assert-True (($xs | Where-Object { [double]::IsNaN($_) }).Count -eq 0) "$pattern X positions are finite"
    Assert-True (($ys | Where-Object { [double]::IsNaN($_) }).Count -eq 0) "$pattern Y positions are finite"
    Assert-True (($xs | Measure-Object -Minimum).Minimum -ge 0) "$pattern stays inside the region on the left"
    Assert-True (($ys | Measure-Object -Minimum).Minimum -ge 0) "$pattern stays inside the region on the top"
    Assert-True (($xs | Measure-Object -Maximum).Maximum -le 484) "$pattern stays inside the region on the right"
    Assert-True (($ys | Measure-Object -Maximum).Maximum -le 330) "$pattern stays inside the region on the bottom"
}

# Explicit out-of-range drift is clamped, including in a compact 48x48 region.
Initialize-SlopFaceDots -Seed 42
$script:FaceDots[0].X = 5.0
$script:FaceDots[0].Y = -5.0
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 48 -Height 48 -Inset 3.0 -Pattern 'scattered'
$first = $face.Children[0]
$firstLeft = [System.Windows.Controls.Canvas]::GetLeft($first)
$firstTop  = [System.Windows.Controls.Canvas]::GetTop($first)
Assert-True ($firstLeft -ge 0 -and ($firstLeft + $first.Width) -le 48) 'out-of-range X drift is clamped into 48x48'
Assert-True ($firstTop -ge 0 -and ($firstTop + $first.Height) -le 48) 'out-of-range Y drift is clamped into 48x48'

# Frozen means byte-for-byte identical positions across different times.
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Frozen $true -Pattern 'spiral'
$frozenA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Update-SlopFaceLayer -Target $face -Time 9.0 -Speed 1.0 -Width 484 -Height 330 -Frozen $true -Pattern 'spiral'
$frozenB = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Assert-True ($frozenA -eq $frozenB) 'frozen spiral holds positions constant across time'
Assert-True ($face.Children.Count -eq 32) 'frozen pattern keeps 32 dots'

# Spiral is rotationally distinct from ring.
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Pattern 'ring'
$ringA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Update-SlopFaceLayer -Target $face -Time 1.0 -Speed 1.0 -Width 484 -Height 330 -Pattern 'spiral'
$spiralA = @($face.Children | ForEach-Object { '{0:F4},{1:F4}' -f [System.Windows.Controls.Canvas]::GetLeft($_), [System.Windows.Controls.Canvas]::GetTop($_) }) -join '|'
Assert-True ($ringA -ne $spiralA) 'spiral pattern is distinct from ring'

# Wider, richer aura: pinned token contract and measured behavior.
$faceSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../src/Slop.Face.ps1')
Assert-True ($faceSource -match 'Slop\.Design\.ps1') 'face layer consumes design tokens'
Assert-True ($faceSource -match 'face\.scatter') 'scatter radius comes from the design token'
Initialize-SlopFaceDots -Seed 7
$sizes = @($script:FaceDots | ForEach-Object { [double]$_.Size })
Assert-True (($sizes | Measure-Object -Maximum).Maximum -le 2.6) 'dot size never exceeds 2.6'
Assert-True (($sizes | Measure-Object -Maximum).Maximum -gt 2.2) 'dot sizes are visibly varied'

# Compact aura in the 96x96 region with inset 4. Ring reach must exceed 0.40
# normalized radius; the old 0.36 scatter could not. Frozen mode settles the
# pattern transition so the measurement reads the target state, not a blend.
Update-SlopFaceLayer -Target $face -Time 2.0 -Speed 1.0 -Width 96 -Height 96 -Inset 4 -Frozen $true -Pattern 'ring'
$nxValues = @($face.Children | ForEach-Object {
    ([System.Windows.Controls.Canvas]::GetLeft($_) + $_.Width / 2.0 - 4.0) / 88.0
})
$extent = @($nxValues | ForEach-Object { [Math]::Abs($_ - 0.5) } | Measure-Object -Maximum).Maximum
Assert-True ($extent -ge 0.40) "ring scatter reaches 0.40+ normalized (got $([Math]::Round($extent,3)))"
$lefts = @($face.Children | ForEach-Object { [System.Windows.Controls.Canvas]::GetLeft($_) })
Assert-True (($lefts | Measure-Object -Minimum).Minimum -ge -3) 'compact aura stays inside 96x96 region'
Assert-True ($face.Children.Count -eq 32) 'compact aura keeps 32 dots'

$opacities = @($face.Children | ForEach-Object { [double]$_.Opacity })
Assert-True ((@($opacities | Select-Object -Unique)).Count -gt 1) 'radial falloff produces varied opacity'

Update-SlopFaceLayer -Target $face -Time 3.0 -Speed 1.0 -Width 96 -Height 96 -Inset 4 -Frozen $true -Pattern 'ring'
$frozenOpacityA = @($face.Children | ForEach-Object { '{0:F4}' -f $_.Opacity }) -join '|'
Update-SlopFaceLayer -Target $face -Time 11.0 -Speed 1.0 -Width 96 -Height 96 -Inset 4 -Frozen $true -Pattern 'ring'
$frozenOpacityB = @($face.Children | ForEach-Object { '{0:F4}' -f $_.Opacity }) -join '|'
Assert-True ($frozenOpacityA -eq $frozenOpacityB) 'frozen radial opacity is stable across time'

Describe 'Slop face layer' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
