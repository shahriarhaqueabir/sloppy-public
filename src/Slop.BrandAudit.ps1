# src/Slop.BrandAudit.ps1 -- pure brand + voice audit. No WPF, no network.
# Reads tracked source, emits deterministic findings, compares a baseline, and
# renders a report. Tokens, copy, and contrast math come from Slop.Design.ps1.
$ErrorActionPreference = 'Stop'

$script:designModule = Join-Path $PSScriptRoot 'Slop.Design.ps1'
if (Test-Path -LiteralPath $script:designModule) { . $script:designModule }

# Semantic art marks may keep literal colours. They are rule exceptions, listed
# here with a reason, not baseline debt.
$script:SlopBrandArtMarks = @(
    'Glyph', 'StatusDot', 'BodyPath', 'HeadHighlight', 'PreviewPea',
    'Particle', 'Face', 'Silhouette'
)

# Compact chrome controls are intentionally below the 24px hit-target floor.
$script:SlopBrandChromeControls = @(
    'ControlDeckButton', 'SettingsDot', 'PinDot', 'CloseDot',
    'ChatDeckButton', 'ChatModeButton', 'ChatCloseButton'
)

# Deterministic phrases banned by agent/BRAND.md: corporate ceremony, fake
# intimacy, human pretend-play, and filler praise/apology/restated premise.
$script:SlopBrandBannedPhrases = @(
    'excited to', 'pleased to', 'delighted to', 'happy to announce',
    'please note', 'rest assured', 'great question', 'kindly',
    'at your earliest convenience', 'circle back', 'in order to',
    'we apologize', 'we apologise', 'sorry for', 'as an ai'
)

$script:SlopBrandLegalCopy = '(?i)terms|privacy|provider|disclosure|training|retention'

function Get-SlopBrandFindingKey {
    param([Parameter(Mandatory)][object]$Finding)
    $file = ([string]$Finding.File).Trim()
    $line = [string]$Finding.Line
    $rule = ([string]$Finding.Rule).Trim()
    $value = ([string]$Finding.Value).Trim() -replace '\s+', ' '
    return "$file|$line|$rule|$value"
}

function Test-SlopBrandArtMark {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    foreach ($mark in $script:SlopBrandArtMarks) {
        if ($Name -like "*$mark*") { return $true }
    }
    return $false
}

function Get-SlopBrandSurfaces {
    param([Parameter(Mandatory)][string]$Root)

    $srcDir = Join-Path $Root 'src'
    if (-not (Test-Path -LiteralPath $srcDir)) { return @() }

    $result = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.ps1' -File | Sort-Object Name)
    foreach ($file in $files) {
        $lines = @(Get-Content -LiteralPath $file.FullName)
        $relative = 'src/' + $file.Name

        # XAML here-strings: open on @' or @", close on a bare '@ or "@ line.
        $open = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($null -eq $open) {
                if ($line.Contains("@'")) { $open = @{ Term = "'@"; Start = $i + 2 } }
                elseif ($line.Contains('@"')) { $open = @{ Term = '"@'; Start = $i + 2 } }
                continue
            }
            if ($line.Trim() -eq $open.Term) {
                if ($open.Start -le $i) {
                    $body = @($lines[($open.Start - 1)..($i - 1)])
                    if (($body -join "`n") -match '<Window') {
                        $result.Add([pscustomobject]@{
                            Surface = $file.BaseName
                            File = $relative
                            Line = $open.Start
                            EndLine = $i
                            Kind = 'Xaml'
                        })
                    }
                }
                $open = $null
            }
        }

        # Code-created dialogs and explicit text assignments.
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '\[System\.Windows\.(Window|MessageBox)\]') {
                $result.Add([pscustomobject]@{
                    Surface = $file.BaseName
                    File = $relative
                    Line = $i + 1
                    EndLine = $i + 1
                    Kind = 'Code'
                })
            }
        }
    }
    return @($result)
}

function Get-SlopBrandTokenValues {
    $values = @{}
    foreach ($key in $script:SlopDesignTokens.Keys) {
        $value = $script:SlopDesignTokens[$key]
        if ($value -is [string]) { $values[$value] = $key }
    }
    return $values
}

function Test-SlopBrandCopyException {
    param([Parameter(Mandatory)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    if ($Value.StartsWith('{')) { return $true }
    if ($Value -match '^\.\.\.') { return $true }
    if ($Value -match '^Say something') { return $true }
    if ($Value -match '^\d+(?:[.,]\d+)*$') { return $true }
    if ($Value -match '^[^\p{L}\p{N}]{1,4}$') { return $true }
    if ($Value -match $script:SlopBrandLegalCopy) { return $true }
    return $false
}

function Get-SlopBrandBannedCopy {
    param([Parameter(Mandatory)][string]$Value)
    foreach ($phrase in $script:SlopBrandBannedPhrases) {
        if ($Value -match [regex]::Escape($phrase)) { return $phrase }
    }
    return $null
}

function New-SlopBrandFinding {
    param(
        [Parameter(Mandatory)][string]$Surface,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][int]$Line,
        [Parameter(Mandatory)][string]$Rule,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [string]$Severity = 'baselined',
        [string]$Reason = ''
    )
    return [pscustomobject]@{
        Surface = $Surface
        File = $File
        Line = $Line
        Rule = $Rule
        Value = $Value
        Severity = $Severity
        Reason = $Reason
    }
}

function Get-SlopBrandFindings {
    param([Parameter(Mandatory)][string]$Root)

    $findings = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $tokenValues = Get-SlopBrandTokenValues
    $copyValues = @{}
    foreach ($key in $script:SlopDesignCopy.Keys) { $copyValues[[string]$script:SlopDesignCopy[$key]] = $key }
    $allowedLiterals = @('transparent', 'auto', '*')

    $addFinding = {
        param($Finding)
        $key = Get-SlopBrandFindingKey -Finding $Finding
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $findings.Add($Finding)
        }
    }

    foreach ($surface in @(Get-SlopBrandSurfaces -Root $Root)) {
        $path = Join-Path $Root ($surface.File -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $lines = @(Get-Content -LiteralPath $path)
        $from = [Math]::Max(0, $surface.Line - 1)
        $to = [Math]::Min($lines.Count - 1, $surface.EndLine - 1)
        $currentName = ''

        for ($i = $from; $i -le $to; $i++) {
            $line = $lines[$i]
            $lineNumber = $i + 1
            $nameMatch = [regex]::Match($line, 'x:Name="([^"]+)"')
            if ($nameMatch.Success) { $currentName = $nameMatch.Groups[1].Value }
            $lineName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { $currentName }

            # Token coverage.
            foreach ($m in [regex]::Matches($line, '\b(Background|Foreground|BorderBrush|Fill|Stroke|FontSize|CornerRadius|Margin)="([^"]*)"')) {
                $attribute = $m.Groups[1].Value
                $value = $m.Groups[2].Value
                if ($value -match '^\{(StaticResource|DynamicResource|TemplateBinding|Binding)\b') { continue }
                if ($allowedLiterals -contains $value.ToLowerInvariant()) { continue }
                if ($tokenValues.ContainsKey($value)) { continue }
                if (Test-SlopBrandArtMark -Name $lineName) { continue }
                if ($attribute -eq 'FontSize' -and $value -match '^\d+$' -and [int]$value -lt 11) {
                    & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'type.floor' -Value $value -Severity 'baselined' -Reason 'font size below type.floor token')
                    continue
                }
                & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'token.literal' -Value $value -Severity 'baselined' -Reason 'legacy literal; reduce surface by surface')
            }

            # Hit-target floor for buttons that are not compact chrome.
            if ($line -match '<Button\b') {
                $w = [regex]::Match($line, '\bWidth="(\d+)"')
                $h = [regex]::Match($line, '\bHeight="(\d+)"')
                if ($w.Success -and $h.Success) {
                    $width = [int]$w.Groups[1].Value
                    $height = [int]$h.Groups[1].Value
                    $isChrome = $false
                    foreach ($chrome in $script:SlopBrandChromeControls) {
                        if ($lineName -like "*$chrome*") { $isChrome = $true; break }
                    }
                    if (-not $isChrome -and ($width -lt 24 -or $height -lt 24)) {
                        & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'hit-target.small' -Value "${width}x${height}" -Severity 'baselined' -Reason 'control below 24px floor')
                    }
                }
            }

            # Copy coverage, including code-created dialog assignments.
            $copyPattern = if ($surface.Kind -eq 'Xaml') {
                '\b(Text|Header|Content|ToolTip)="([^"]*)"'
            } else {
                '\.(Text|Header|Content|ToolTip)\s*=\s*[''"]{1}([^''"]+)[''"]{1}'
            }
            foreach ($m in [regex]::Matches($line, $copyPattern)) {
                $value = $m.Groups[2].Value
                if ($copyValues.ContainsKey($value)) { continue }
                if (Test-SlopBrandCopyException -Value $value) { continue }
                $banned = Get-SlopBrandBannedCopy -Value $value
                if ($banned) {
                    & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'copy.voice' -Value $value -Severity 'baselined' -Reason "banned voice phrase: $banned")
                } else {
                    & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'copy.literal' -Value $value -Severity 'baselined' -Reason 'static copy not mapped to canonical key')
                }
            }

            # Absolute-path and credential-like defence in depth.
            if ($line -match '([A-Za-z]:\\\\[^\s"''<>]+|/home/[^\s"''<>]+|/Users/[^\s"''<>]+)') {
                & $addFinding (New-SlopBrandFinding -Surface $surface.Surface -File $surface.File -Line $lineNumber -Rule 'path.absolute' -Value $Matches[1] -Severity 'hard' -Reason 'absolute machine path in tracked source')
            }
        }
    }

    return @($findings)
}

function Test-SlopBrandContrast {
    param(
        [Parameter(Mandatory)][string]$Foreground,
        [Parameter(Mandatory)][string]$Background
    )
    return (Test-SlopContrast -Foreground $Foreground -Background $Background)
}

function Compare-SlopBrandBaseline {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Baseline
    )

    $baselineByKey = @{}
    foreach ($entry in $Baseline) {
        $key = Get-SlopBrandFindingKey -Finding $entry
        $baselineByKey[$key] = $entry
    }

    $new = [System.Collections.Generic.List[object]]::new()
    $missingReason = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[object]]::new()
    $currentKeys = @{}

    foreach ($finding in $Findings) {
        $key = Get-SlopBrandFindingKey -Finding $finding
        $currentKeys[$key] = $true
        if ([string]$finding.Severity -eq 'hard') {
            $errors.Add($finding)
            continue
        }
        if (-not $baselineByKey.ContainsKey($key)) {
            $new.Add($finding)
            continue
        }
        $entry = $baselineByKey[$key]
        if ([string]::IsNullOrWhiteSpace([string]$entry.Reason)) {
            $missingReason.Add($finding)
        }
    }

    $stale = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $baselineByKey.Keys) {
        if (-not $currentKeys.ContainsKey($key)) { $stale.Add($baselineByKey[$key]) }
    }

    $ok = ($errors.Count -eq 0 -and $new.Count -eq 0 -and $missingReason.Count -eq 0)
    return [pscustomobject]@{
        Ok = $ok
        New = @($new)
        MissingReason = @($missingReason)
        Stale = @($stale)
        Errors = @($errors)
    }
}

function New-SlopBrandReport {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Sloppy brand and voice audit')
    $lines.Add('')
    $lines.Add('Generated from tracked source by `src/Slop.BrandAudit.ps1`. This is a')
    $lines.Add('ratchet baseline, not approval of the listed copy or literals.')
    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')
    $lines.Add('| surface | file | line | rule | value | severity | exception reason |')
    $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
    foreach ($finding in $Findings) {
        $cells = @(
            $finding.Surface, $finding.File, $finding.Line, $finding.Rule,
            $finding.Value, $finding.Severity, $finding.Reason
        ) | ForEach-Object { ([string]$_).Replace('|', '\|').Replace("`n", ' ') }
        $lines.Add('| ' + ($cells -join ' | ') + ' |')
    }
    $lines.Add('')

    $bySurface = @($Findings | Group-Object Surface | Sort-Object Name)
    $byRule = @($Findings | Group-Object Rule | Sort-Object Name)
    $lines.Add('## Summary')
    $lines.Add('')
    $lines.Add("- Total findings: $($Findings.Count)")
    $lines.Add('- By surface: ' + (($bySurface | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))
    $lines.Add('- By rule: ' + (($byRule | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))
    $lines.Add('- Accepted baseline: see `tests/slop-brand-baseline.json`.')
    $lines.Add('- Hard failures: ' + @($Findings | Where-Object { $_.Severity -eq 'hard' }).Count)
    $lines.Add('')

    $lines.Add('## Rule exceptions')
    $lines.Add('')
    $lines.Add('- Semantic art marks keep literal colours: ' + ($script:SlopBrandArtMarks -join ', ') + '.')
    $lines.Add('- Compact chrome controls are exempt from the 24px hit-target floor: ' + ($script:SlopBrandChromeControls -join ', ') + '.')
    $lines.Add('- Binding expressions, numeric counts, glyph-only controls, legal/terms copy, and user placeholders are copy exceptions.')
    $lines.Add('')

    $lines.Add('## Voice profile')
    $lines.Add('')
    $lines.Add('Author: Sloppy companion voice.')
    $lines.Add('')
    $lines.Add('Goal: keep UI copy warm, low-key, honest, and concise.')
    $lines.Add('')
    $lines.Add('Confidence: medium. Source set is short but canonical.')
    $lines.Add('')
    $lines.Add('Source Set')
    $lines.Add('- agent/BRAND.md')
    $lines.Add('- agent/SLOPPY.md')
    $lines.Add('- agent/abilities/*.md')
    $lines.Add('- src/Slop.Design.ps1 SlopDesignCopy')
    $lines.Add('')
    $lines.Add('Rhythm')
    $lines.Add('- Short sentences; lead with the answer, then the trade-off.')
    $lines.Add('')
    $lines.Add('Compression')
    $lines.Add('- Dense. Remove any sentence that does not change meaning.')
    $lines.Add('')
    $lines.Add('Capitalization')
    $lines.Add('- Conventional sentence case; product marks are stable.')
    $lines.Add('')
    $lines.Add('Parentheticals')
    $lines.Add('- Rare; only for a real qualification, never for padding.')
    $lines.Add('')
    $lines.Add('Question Use')
    $lines.Add('- Direct and occasional; no rhetorical filler.')
    $lines.Add('')
    $lines.Add('Claim Style')
    $lines.Add('- Name the real outcome; never claim work that was not done.')
    $lines.Add('')
    $lines.Add('Preferred Moves')
    $lines.Add('- Plain words for consequential actions.')
    $lines.Add('- Dry technical wit, used sparingly.')
    $lines.Add('')
    $lines.Add('Banned Moves')
    $lines.Add('- Corporate ceremony, fake intimacy, human pretend-play.')
    $lines.Add('- Filler praise, apologies, and restated premises.')
    $lines.Add('')
    $lines.Add('CTA Rules')
    $lines.Add('- Ask only when a decision is actually needed.')
    $lines.Add('')
    $lines.Add('Channel Notes')
    $lines.Add('- In-app: compact, status-adjacent copy.')
    $lines.Add('- Onboarding: plain, honest, never salesy.')
    $lines.Add('- Dialogs: name the consequence before asking for confirmation.')
    $lines.Add('')

    return ($lines -join "`n")
}

function Test-SlopBrandGate {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$BaselinePath
    )

    $findings = @(Get-SlopBrandFindings -Root $Root)
    $baseline = @()
    if ($BaselinePath -and (Test-Path -LiteralPath $BaselinePath)) {
        $raw = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
        $baseline = @($raw)
    }
    $comparison = Compare-SlopBrandBaseline -Findings $findings -Baseline $baseline
    return [pscustomobject]@{
        Ok = $comparison.Ok
        New = $comparison.New
        MissingReason = $comparison.MissingReason
        Stale = $comparison.Stale
        Errors = $comparison.Errors
        Findings = $findings
        Report = (New-SlopBrandReport -Findings $findings)
    }
}
