# Pure pane geometry and pet visibility. No WPF, no registry, no network.
$ErrorActionPreference = 'Stop'

function Get-SlopFullPaneRect {
    param([Parameter(Mandatory)][hashtable]$WorkArea)
    $marginX = [int][math]::Round([double]$WorkArea.Width * 0.0583333333)
    $marginY = [int][math]::Round([double]$WorkArea.Height * 0.0692307692)
    $left = [int]$WorkArea.X + $marginX
    $top = [int]$WorkArea.Y + $marginY
    $width = [int]$WorkArea.Width - (2 * $marginX)
    $height = [int]$WorkArea.Height - (2 * $marginY)
    return @{
        Left = $left; Top = $top; Width = $width; Height = $height
    }
}

function Get-SlopMovedPaneRect {
    param(
        [Parameter(Mandatory)][hashtable]$Rect,
        [int]$DeltaX = 0,
        [int]$DeltaY = 0,
        [Parameter(Mandatory)][hashtable]$WorkArea
    )
    $left = [int]$Rect.Left + $DeltaX
    $top = [int]$Rect.Top + $DeltaY
    $right = $left + [int]$Rect.Width
    $bottom = $top + [int]$Rect.Height
    if ($left -lt [int]$WorkArea.X) { $left = [int]$WorkArea.X }
    if ($top -lt [int]$WorkArea.Y) { $top = [int]$WorkArea.Y }
    if ($right -gt ([int]$WorkArea.X + [int]$WorkArea.Width)) {
        $left = [int]$WorkArea.X + [int]$WorkArea.Width - [int]$Rect.Width
    }
    if ($bottom -gt ([int]$WorkArea.Y + [int]$WorkArea.Height)) {
        $top = [int]$WorkArea.Y + [int]$WorkArea.Height - [int]$Rect.Height
    }
    return @{
        Left = $left; Top = $top
        Width = [int]$Rect.Width; Height = [int]$Rect.Height
    }
}

function Get-SlopPinnedAwareChatRect {
    param(
        [Parameter(Mandatory)][hashtable]$PetRect,
        [Parameter(Mandatory)][hashtable]$RequestedRect,
        [Parameter(Mandatory)][hashtable]$WorkArea,
        [int]$Gap = 16
    )
    $petLeft = [int]$PetRect.Left
    $petTop = [int]$PetRect.Top
    $petRight = $petLeft + [int]$PetRect.Width
    $petBottom = $petTop + [int]$PetRect.Height
    $rqLeft = [int]$RequestedRect.Left
    $rqTop = [int]$RequestedRect.Top
    $rqWidth = [int]$RequestedRect.Width
    $rqHeight = [int]$RequestedRect.Height
    $rqRight = $rqLeft + $rqWidth
    $rqBottom = $rqTop + $rqHeight
    $intersects = -not ($rqRight -le $petLeft -or $rqLeft -ge $petRight -or
                         $rqBottom -le $petTop -or $rqTop -ge $petBottom)
    if (-not $intersects) {
        return Get-SlopMovedPaneRect -Rect $RequestedRect -DeltaX 0 -DeltaY 0 -WorkArea $WorkArea
    }
    $rightSpace = ([int]$WorkArea.X + [int]$WorkArea.Width) - $petRight - $Gap
    $leftSpace = $petLeft - [int]$WorkArea.X - $Gap
    $left = $rqLeft
    if ($rightSpace -ge $rqWidth) {
        $left = $petRight + $Gap
    } elseif ($leftSpace -ge $rqWidth) {
        $left = $petLeft - $Gap - $rqWidth
    }
    $candidate = @{ Left = $left; Top = $rqTop; Width = $rqWidth; Height = $rqHeight }
    return Get-SlopMovedPaneRect -Rect $candidate -DeltaX 0 -DeltaY 0 -WorkArea $WorkArea
}

function Test-SlopPaneClampNeeded {
    param(
        [int]$Value,
        [int]$Minimum,
        [int]$Maximum,
        [int]$Tolerance = 4
    )
    if ($Value -lt $Minimum -and ($Minimum - $Value) -gt $Tolerance) { return $true }
    if ($Value -gt $Maximum -and ($Value - $Maximum) -gt $Tolerance) { return $true }
    return $false
}

function Get-SlopPetRectDuringChat {
    param(
        [Parameter(Mandatory)][hashtable]$PetRect,
        [Parameter(Mandatory)][ValidateSet('Extended','Full')][string]$ChatMode
    )
    # The pet rect is never derived from the chat pane; return the stored rect
    # unchanged so hide/restore cannot drift.
    return Get-SlopRestoredPetRect -StoredRect $PetRect
}

function Get-SlopPanePetState {
    param(
        [Parameter(Mandatory)][ValidateSet('Extended','Full')][string]$ChatMode,
        [bool]$ChatOpen = $false
    )
    if ($ChatOpen -and $ChatMode -eq 'Full') {
        return @{ Visible = $false; Interactive = $false; Topmost = $false }
    }
    return @{ Visible = $true; Interactive = $true; Topmost = $true }
}

function Get-SlopRestoredPetRect {
    param([Parameter(Mandatory)][hashtable]$StoredRect)
    return @{
        Left = [int]$StoredRect.Left; Top = [int]$StoredRect.Top
        Width = [int]$StoredRect.Width; Height = [int]$StoredRect.Height
    }
}

function Get-SlopChatDragGripRect {
    param([int]$Width = 760, [int]$Height = 540)
    return @{ Left = 0; Top = 0; Width = [int]$Width; Height = 32 }
}
