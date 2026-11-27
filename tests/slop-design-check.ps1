# Headless checks for the pure design-token layer. No WPF window is built.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

$module = Join-Path $PSScriptRoot '../src/Slop.Design.ps1'
$moduleExists = Test-Path -LiteralPath $module
if ($moduleExists) { . $module }

$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([string]$Message, [scriptblock]$Test)
    $passed = $false
    if ($moduleExists) {
        try { $passed = [bool](& $Test) } catch { $passed = $false }
    }
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = $passed })
}

$source = if ($moduleExists) { Get-Content -Raw -LiteralPath $module } else { '' }
$token = { param($n) Get-SlopDesignToken -Name $n }

Assert-True 'design token module exists' { $moduleExists }
Assert-True 'Get-SlopDesignToken is exported' { Test-Path 'function:Get-SlopDesignToken' }
Assert-True 'Get-SlopCopy is exported' { Test-Path 'function:Get-SlopCopy' }
Assert-True 'Test-SlopContrast is exported' { Test-Path 'function:Test-SlopContrast' }
Assert-True 'token layer contains no WPF types' { $source -notmatch 'System\.Windows' }

Assert-True 'surface.app is #12141C' { (& $token 'surface.app') -eq '#12141C' }
Assert-True 'surface.panel is #1E293B' { (& $token 'surface.panel') -eq '#1E293B' }
Assert-True 'surface.glass is #18FFFFFF' { (& $token 'surface.glass') -eq '#18FFFFFF' }
Assert-True 'text.primary is #EAEAEA' { (& $token 'text.primary') -eq '#EAEAEA' }
Assert-True 'text.secondary is #B8B8C0' { (& $token 'text.secondary') -eq '#B8B8C0' }
Assert-True 'text.subtle is #93A4BD' { (& $token 'text.subtle') -eq '#93A4BD' }
Assert-True 'text.accent is #A5B4FC' { (& $token 'text.accent') -eq '#A5B4FC' }
Assert-True 'retired #8A8A96 is absent from the module' { $source -notmatch '8A8A96' }
Assert-True 'fill.primary is #4F46E5' { (& $token 'fill.primary') -eq '#4F46E5' }
Assert-True 'fill.destructive is #7F1D1D' { (& $token 'fill.destructive') -eq '#7F1D1D' }
Assert-True 'status.error text is #FCA5A5' { (& $token 'status.text.error') -eq '#FCA5A5' }
Assert-True 'status.thinking text is #FDE68A' { (& $token 'status.text.thinking') -eq '#FDE68A' }
Assert-True 'status.success text is #86EFAC' { (& $token 'status.text.success') -eq '#86EFAC' }
Assert-True 'type floor is 11px' { [double](& $token 'type.floor') -eq 11 }
Assert-True 'pet motion duration is 500ms' { [double](& $token 'motion.duration.pet') -eq 500 }
Assert-True 'ambient motion duration is 1000ms' { [double](& $token 'motion.duration.ambient') -eq 1000 }

$glassComposite = '#282A31'
Assert-True 'primary text meets AA on glass' { (Test-SlopContrast -Foreground '#EAEAEA' -Background $glassComposite) -ge 4.5 }
Assert-True 'secondary text meets AA on glass' { (Test-SlopContrast -Foreground '#B8B8C0' -Background $glassComposite) -ge 4.5 }
Assert-True 'subtle text meets AA on glass' { (Test-SlopContrast -Foreground '#93A4BD' -Background $glassComposite) -ge 4.5 }
Assert-True 'accent text meets AA on glass' { (Test-SlopContrast -Foreground '#A5B4FC' -Background $glassComposite) -ge 4.5 }
Assert-True 'white on primary fill meets AA' { (Test-SlopContrast -Foreground '#FFFFFF' -Background '#4F46E5') -ge 4.5 }
Assert-True 'old ocean fill with white text is not selected' { (& $token 'fill.primary') -ne '#6366F1' }

Assert-True 'copy mark is S.L.O.P.' { (Get-SlopCopy -Key 'mark') -eq 'S.L.O.P.' }
Assert-True 'copy product name is Sloppy' { (Get-SlopCopy -Key 'product') -eq 'Sloppy' }
foreach ($state in @('idle','thinking','working','success','error')) {
    Assert-True "status '$state' has a text label" { -not [string]::IsNullOrWhiteSpace((Get-SlopCopy -Key "status.$state")) }
}

Describe 'Slop design tokens' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
