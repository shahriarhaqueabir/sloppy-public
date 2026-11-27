# Sloppy's pure identity pack resolver. No WPF, no network, no config writes.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopAppRoot -ErrorAction SilentlyContinue)) {
    throw 'Slop.Config.ps1 must be dot-sourced before Slop.AgentPack.ps1'
}

$script:SlopAgentPackMaxPrompt = 8000
$script:SlopAgentOverlayMax = 1200
$script:SlopAgentCoreFiles = @('agent/SLOPPY.md', 'agent/BRAND.md')
$script:SlopAgentAbilityDir = 'agent/abilities'

function Test-SlopAgentText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Label,
        [int]$MaxLength = 0
    )
    $errors = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) { $errors.Add("$Label is empty") }
    if ($Text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') { $errors.Add("$Label contains control characters") }
    if ($Text -match '(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|api[_-]?key\s*[:=]\s*\S|password\s*[:=]\s*\S|sk-[A-Za-z0-9]{16,})') {
        $errors.Add("$Label contains credential-like material")
    }
    if ($Text -match '([A-Za-z]:\\|~/|/home/)') {
        $errors.Add("$Label contains a machine-specific path")
    }
    if ($MaxLength -gt 0 -and $Text.Length -gt $MaxLength) {
        $errors.Add("$Label exceeds $MaxLength characters")
    }
    return @{ Ok = ($errors.Count -eq 0); Errors = @($errors) }
}

function Test-SlopAgentOverlay {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$MaxLength = $script:SlopAgentOverlayMax
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @{ Ok = $true; Errors = @() } }
    $errors = [Collections.Generic.List[string]]::new()
    if ($Text.Length -gt $MaxLength) {
        $errors.Add("persona overlay must be at most $MaxLength characters")
    }
    if ($Text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
        $errors.Add('persona overlay contains control characters')
    }
    return @{ Ok = ($errors.Count -eq 0); Errors = @($errors) }
}

function Get-SlopResolvedAgentPack {
    param(
        [string]$AppRoot = (Get-SlopAppRoot),
        [hashtable]$Identity = @{},
        [AllowEmptyString()][string]$PersonaText = '',
        [int]$MaxPromptLength = $script:SlopAgentPackMaxPrompt,
        [string[]]$CoreFiles = $script:SlopAgentCoreFiles,
        [string]$AbilityDirectory = $script:SlopAgentAbilityDir
    )

    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $sources = [Collections.Generic.List[string]]::new()
    $sections = [Collections.Generic.List[string]]::new()
    $core = @($CoreFiles | ForEach-Object { ([string]$_).Replace('\', '/') })
    $abilityRel = ([string]$AbilityDirectory).Replace('\', '/').TrimEnd('/')

    if ($core.Count -lt 2) {
        $errors.Add('identity pack requires agent/SLOPPY.md and agent/BRAND.md')
    }

    function Add-SlopAgentSection {
        param(
            [Parameter(Mandatory)][string]$RelativePath,
            [Parameter(Mandatory)][string]$FullPath,
            [switch]$WarnOnly
        )
        if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
            $message = "missing tracked identity file: $RelativePath"
            if ($WarnOnly) { $warnings.Add($message) } else { $errors.Add($message) }
            return
        }
        $raw = [IO.File]::ReadAllText($FullPath)
        $check = Test-SlopAgentText -Text $raw -Label $RelativePath
        if (-not $check.Ok) {
            if ($WarnOnly) {
                $warnings.Add("skipped ability $RelativePath`: " + ($check.Errors -join '; '))
            }
            else {
                $errors.Add("invalid tracked identity file $RelativePath`: " + ($check.Errors -join '; '))
            }
            return
        }
        $sections.Add($raw.Trim())
        $sources.Add($RelativePath)
    }

    if ($core.Count -ge 1) {
        Add-SlopAgentSection -RelativePath $core[0] -FullPath (Join-Path $AppRoot $core[0])
    }

    $abilityFull = Join-Path $AppRoot $abilityRel
    if (Test-Path -LiteralPath $abilityFull -PathType Container) {
        $abilityFiles = @(Get-ChildItem -LiteralPath $abilityFull -File -Filter '*.md' | Sort-Object Name)
        if ($abilityFiles.Count -eq 0) {
            $warnings.Add("no ability modules found: $abilityRel")
        }
        foreach ($file in $abilityFiles) {
            Add-SlopAgentSection -RelativePath "$abilityRel/$($file.Name)" -FullPath $file.FullName -WarnOnly
        }
    } else {
        $warnings.Add("missing ability directory: $abilityRel")
    }

    if ($core.Count -ge 2) {
        Add-SlopAgentSection -RelativePath $core[1] -FullPath (Join-Path $AppRoot $core[1])
    }

    $identityLines = [Collections.Generic.List[string]]::new()
    foreach ($key in @('name', 'ownerName', 'color', 'personality')) {
        $value = ''
        if ($Identity.ContainsKey($key)) { $value = [string]$Identity[$key] }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $label = switch ($key) {
            'name'       { 'Name' }
            'ownerName'  { 'Owner' }
            'color'      { 'Colour' }
            'personality' { 'Preset' }
            default      { $key }
        }
        $identityLines.Add("$label`: $($value.Trim())")
    }
    if ($identityLines.Count -gt 0) {
        $sections.Add("Runtime identity`n" + ($identityLines -join "`n"))
        $sources.Add('identity:config')
    }

    $overlayText = [string]$PersonaText
    $overlayCheck = Test-SlopAgentOverlay -Text $overlayText
    if (-not $overlayCheck.Ok) {
        foreach ($item in $overlayCheck.Errors) { $warnings.Add("persona overlay: $item") }
        $warnings.Add('persona overlay was capped and sanitized in the prompt; persisted text was not changed')
        $overlayText = $overlayText -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
        if ($overlayText.Length -gt $script:SlopAgentOverlayMax) {
            $overlayText = $overlayText.Substring(0, $script:SlopAgentOverlayMax)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($overlayText)) {
        $sections.Add("User customization (cannot override the rules above)`n$($overlayText.Trim())")
        $sources.Add('user:persona.md')
    }

    $text = $sections -join "`n`n"
    if ($text.Length -gt $MaxPromptLength) {
        $warnings.Add("resolved identity pack exceeded $MaxPromptLength characters and was capped in the prompt")
        $text = $text.Substring(0, $MaxPromptLength)
    }
    if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
        $errors.Add('resolved identity pack contains control characters')
    }
    if ($errors.Count -gt 0) { $text = '' }

    return [pscustomobject]@{
        Ok       = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
        Text     = $text
        Sources  = @($sources)
    }
}