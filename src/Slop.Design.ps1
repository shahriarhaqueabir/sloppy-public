# src/Slop.Design.ps1 -- pure design tokens and canonical UI copy.
# No UI framework types live here. WPF callers build brushes from these values.
$ErrorActionPreference = 'Stop'

$script:SlopDesignTokens = [ordered]@{
    # Surfaces. The glass fill is applied over surface.app only; a dark backplate
    # keeps text contrast independent of the user's wallpaper.
    'surface.app'          = '#12141C'
    'surface.panel'        = '#1E293B'
    'surface.raised'       = '#263348'
    'surface.glass'        = '#18FFFFFF'
    'surface.scrim'        = '#B3000000'
    'surface.glass.composite' = '#282A31'

    # Text and icon roles. Informational text uses these light variants, never
    # the raw identity marks.
    'text.primary'         = '#EAEAEA'
    'text.secondary'       = '#B8B8C0'
    'text.subtle'          = '#93A4BD'
    'text.accent'          = '#A5B4FC'
    'text.focus'           = '#93C5FD'
    'text.thinking'        = '#FDE68A'
    'text.success'         = '#86EFAC'
    'text.error'           = '#FCA5A5'

    # Filled controls. White on fill.primary is 6.29:1; the old lighter ocean
    # value sat just under AA and is kept only as a decorative mark.
    'fill.primary'         = '#4F46E5'
    'fill.primary.hover'   = '#4338CA'
    'fill.secondary'       = '#14B8A6'
    'fill.destructive'     = '#7F1D1D'

    # Identity marks, unchanged from the existing product palette.
    'mark.ocean'           = '#6366F1'
    'mark.moss'            = '#14B8A6'
    'mark.plum'            = '#A855F7'
    'mark.ember'           = '#EC4899'
    'mark.sky'             = '#38BDF8'
    'mark.stone'           = '#94A3B8'

    # Status text roles. Colour is always paired with a label and a shape.
    'status.text.idle'     = '#A5B4FC'
    'status.text.thinking' = '#FDE68A'
    'status.text.working'  = '#86EFAC'
    'status.text.success'  = '#86EFAC'
    'status.text.error'    = '#FCA5A5'

    # Type scale in the WPF font-size unit already used by the app.
    'type.floor'           = 11
    'type.caption'         = 11
    'type.label'           = 12
    'type.body'            = 14
    'type.title'           = 18
    'type.display'         = 24

    # Spacing and radius.
    'space.1'              = 4
    'space.2'              = 8
    'space.3'              = 12
    'space.4'              = 16
    'space.5'              = 24
    'space.6'              = 32
    'radius.control'       = 8
    'radius.bubble'        = 12
    'radius.card'          = 16

    # Motion durations in milliseconds. Ambient motion is pausable and disabled
    # under reduced motion.
    'motion.duration.quick'   = 100
    'motion.duration.control' = 200
    'motion.duration.panel'   = 300
    'motion.duration.pet'     = 500
    'motion.duration.ambient' = 1000

    # Standard and emphasized decelerate/accelerate curves as cubic bezier quads.
    'motion.easing.standard'              = @(0.2, 0.0, 0.0, 1.0)
    'motion.easing.standard.decelerate'   = @(0.0, 0.0, 0.0, 1.0)
    'motion.easing.standard.accelerate'   = @(0.3, 0.0, 1.0, 1.0)
    'motion.easing.emphasized.decelerate' = @(0.05, 0.7, 0.1, 1.0)
    'motion.easing.emphasized.accelerate' = @(0.3, 0.0, 0.8, 0.15)

    # Particle field contract consumed by Slop.Face.ps1.
    'face.count'           = 32
    'face.scatter'         = 0.46
    'face.size.min'        = 1.0
    'face.size.max'        = 2.6
    'face.region.compact'  = 96
    'face.inset.compact'   = 4
}

$script:SlopDesignCopy = [ordered]@{
    'product'               = 'Sloppy'
    'mark'                  = 'S.L.O.P.'
    'status.idle'           = 'Idle'
    'status.thinking'       = 'Thinking'
    'status.working'        = 'Working'
    'status.success'        = 'Done'
    'status.error'          = 'Needs you'
    'advanced'              = 'Advanced'
    'advanced.help'         = 'Raw values for people who need them.'
    'route.local'           = 'Local route: chat text stays on this PC.'
    'route.opencode'        = 'OpenCode route: chat text goes to the configured service.'
    'voice.optin'           = 'Voice input (local transcription, off by default)'
    'voice.notready'        = 'Voice input is not ready. Check local transcription files.'
    'reply.failed'          = 'Could not reach the model. Nothing was sent.'
    'saved'                 = 'Done. Settings saved.'
}

function Get-SlopDesignToken {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:SlopDesignTokens.Contains($Name)) {
        throw "Unknown design token: $Name"
    }
    return $script:SlopDesignTokens[$Name]
}

function Get-SlopCopy {
    param([Parameter(Mandatory)][string]$Key)
    if (-not $script:SlopDesignCopy.Contains($Key)) {
        throw "Unknown copy key: $Key"
    }
    return $script:SlopDesignCopy[$Key]
}

function Get-SlopLinearChannel {
    param([double]$Channel)
    $c = $Channel / 255.0
    if ($c -le 0.04045) { return $c / 12.92 }
    return [Math]::Pow(($c + 0.055) / 1.055, 2.4)
}

function Get-SlopRelativeLuminance {
    param([string]$Hex)
    $value = $Hex.TrimStart('#')
    if ($value.Length -eq 3) {
        $value = -join ($value.ToCharArray() | ForEach-Object { "$_$_" })
    }
    if ($value.Length -ne 6) { throw "Expected a six-digit hex colour, got: $Hex" }
    $r = [Convert]::ToInt32($value.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($value.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($value.Substring(4, 2), 16)
    $rl = Get-SlopLinearChannel -Channel $r
    $gl = Get-SlopLinearChannel -Channel $g
    $bl = Get-SlopLinearChannel -Channel $b
    return (0.2126 * $rl) + (0.7152 * $gl) + (0.0722 * $bl)
}

function Test-SlopContrast {
    param(
        [Parameter(Mandatory)][string]$Foreground,
        [Parameter(Mandatory)][string]$Background
    )
    $a = Get-SlopRelativeLuminance -Hex $Foreground
    $b = Get-SlopRelativeLuminance -Hex $Background
    $light = [Math]::Max($a, $b)
    $dark = [Math]::Min($a, $b)
    return ($light + 0.05) / ($dark + 0.05)
}

# Named component roles. These are contracts for the audit, not XAML resource
# keys: surfaces may keep local resources while the roles stay the source of
# truth for token pairing and minimum control size.
$script:SlopBrandStyleRoles = [ordered]@{
    'slop.button.primary'   = [pscustomobject]@{
        Token = 'fill.primary'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.button.secondary' = [pscustomobject]@{
        Token = 'surface.raised'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.button.danger'    = [pscustomobject]@{
        Token = 'fill.destructive'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.input'            = [pscustomobject]@{
        Token = 'surface.panel'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.checkbox'         = [pscustomobject]@{
        Token = 'surface.panel'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.combo'            = [pscustomobject]@{
        Token = 'surface.panel'; TextToken = 'text.primary'; MinSize = 24
    }
    'slop.card'             = [pscustomobject]@{
        Token = 'surface.panel'; TextToken = 'text.primary'
    }
    'slop.header'           = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'text.primary'
    }
    'slop.status.idle'      = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'status.text.idle'
    }
    'slop.status.thinking'  = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'status.text.thinking'
    }
    'slop.status.working'   = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'status.text.working'
    }
    'slop.status.success'   = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'status.text.success'
    }
    'slop.status.error'     = [pscustomobject]@{
        Token = 'surface.app'; TextToken = 'status.text.error'
    }
}

function Get-SlopStyleRole {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:SlopBrandStyleRoles.Contains($Name)) {
        throw "Unknown component style role: $Name"
    }
    $role = $script:SlopBrandStyleRoles[$Name]
    return [pscustomobject]@{
        Name = $Name
        Token = $role.Token
        TextToken = $role.TextToken
        MinSize = if ($role.PSObject.Properties.Name -contains 'MinSize') { $role.MinSize } else { $null }
    }
}
