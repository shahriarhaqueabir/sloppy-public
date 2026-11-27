# Pane movement, control deck, capability toggles, selectable text, and shutdown — implementation plan

## Status

- Approved design: `docs/plans/2026-11-27-pane-movement-control-deck-design.md` (commit `fdc7ef4`).
- Implementation approach: Approach A — pure headless cores with thin WPF wiring.
- Execution gate: do not implement until this plan is committed and the user explicitly approves execution.
- Execution mode: inline on `main`; no subagents.
- Verification policy: RED → GREEN with a `test:` reproducer committed before each GREEN change.

## Scope and non-goals

This plan implements the accepted three-view baseline with movable panes, a six-section control deck, six default-off capability toggles, selectable conversation text, and a confirmed shutdown phrase.

It does not implement a true OS/work-area-filling fullscreen, a Copy button, clipboard helpers, TTS/read-aloud, a new audio backend, raw permission JSON editing, a private PSloppy port, or a new top-level sidebar window. The WPF transparency contract stays `WindowStyle="None"`, `AllowsTransparency="True"`, `Background="Transparent"`.

## Architecture

### Source files

- `src/Slop.PaneMovement.ps1` — pure pane geometry, pin-aware placement, clamp tolerance, and pet visibility state.
- `src/Slop.CapabilityToggles.ps1` — toggle key set, defaults, validation, capability-profile resolver, and disclosure copy.
- `src/Slop.ControlDeck.ps1` — section catalog, toggle metadata, and deck content contract.
- `src/Slop.Shutdown.ps1` — phrase normalization, yes/no confirmation resolver, and clean teardown step catalog.
- `src/Slop.ChatWindow.ps1` — add drag-grip and pin-aware geometry helpers; keep transparent chat window contract.
- `src/Slop.Config.ps1` — add default `capabilityToggles` to v3 defaults and existing v3 configs via the existing default-key copy in `Read-SlopConfig`; no version bump.
- `src/Slop.OpenCodeProfile.ps1` — accept a resolved capability set when generating profiles; hard denies remain immutable.
- `src/Slop.ps1` — wire drag gestures, mode switching, deck UI, text selection, toggle saves, and shutdown.

### Test files

- `tests/slop-pane-movement-check.ps1`
- `tests/slop-capability-toggle-check.ps1`
- `tests/slop-control-deck-check.ps1`
- `tests/slop-shutdown-phrase-check.ps1`
- Existing contracts extended: `tests/slop-transparency-check.ps1`, `tests/slop-shell-check.ps1`, `tests/slop-config-check.ps1`, `tests/slop-opencode-profile-check.ps1`, `tests/slop-ia-check.ps1`, `tests/slop-tour-check.ps1`.

### State ownership

- Pane geometry helpers are pure functions in headless modules; WPF handlers only read/write control properties and call helpers.
- The pet window rect is stored once when `Full` is entered and restored unchanged when leaving `Full`.
- `Extended` keeps the pea visible and interactive at its exact rect; `Full` hides it.
- Chat placement is pin-aware only at open and mode switch; deliberate drags may overlap the pet.
- `LocationChanged` clamps with a small tolerance so a transparent topmost pane does not oscillate.
- Drag gestures move only the chat pane; they never move or resize the pet.
- `Sloppy, shutdown` and all confirmation input resolve through one pure function before `Start-Stream`.

## Task 1 — Pane geometry and mode-aware pet visibility

### RED reproducer

Create `tests/slop-pane-movement-check.ps1` with Pester 6:

```powershell
#requires -Version 7.6
Describe 'Slop pane movement' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.PaneMovement.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1')
    }

    It 'uses a large inset preset for Full mode, not the whole work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopFullPaneRect -WorkArea $wa
        $r.Left | Should -Be 112
        $r.Top | Should -Be 72
        $r.Width | Should -Be 1696
        $r.Height | Should -Be 896
        $r.Left | Should -BeGreaterThan $wa.X
        $r.Top | Should -BeGreaterThan $wa.Y
        ($r.Left + $r.Width) | Should -BeLessThan ($wa.X + $wa.Width)
        ($r.Top + $r.Height) | Should -BeLessThan ($wa.Y + $wa.Height)
    }

    It 'moves a pane by a drag delta and clamps it inside the work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopMovedPaneRect -Rect @{ Left = 112; Top = 72; Width = 760; Height = 540 } `
            -DeltaX 2000 -DeltaY -500 -WorkArea $wa
        $r.Left | Should -Be 1160
        $r.Top | Should -Be 0
        $r.Width | Should -Be 760
        $r.Height | Should -Be 540
    }

    It 'keeps the pet visible and interactive in Extended but hidden in Full' {
        $extended = Get-SlopPanePetState -ChatMode Extended -ChatOpen $true
        $extended.Visible | Should -BeTrue
        $extended.Interactive | Should -BeTrue
        $extended.Topmost | Should -BeTrue

        $full = Get-SlopPanePetState -ChatMode Full -ChatOpen $true
        $full.Visible | Should -BeFalse
        $full.Interactive | Should -BeFalse
        $full.Topmost | Should -BeFalse
    }

    It 'restores the stored pet rect unchanged when Full closes' {
        $stored = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $restored = Get-SlopRestoredPetRect -StoredRect $stored
        $restored.Left | Should -Be 412
        $restored.Top | Should -Be 390
        $restored.Width | Should -Be 484
        $restored.Height | Should -Be 330
    }

    It 'exposes a drag grip helper that preserves pane size' {
        $grip = Get-SlopChatDragGripRect -Width 760 -Height 540
        $grip.Left | Should -Be 0
        $grip.Top | Should -Be 0
        $grip.Width | Should -Be 760
        $grip.Height | Should -Be 32
    }

    It 'offsets the opening chat away from a pinned pet' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $pet = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $r = Get-SlopPinnedAwareChatRect -PetRect $pet `
            -RequestedRect @{ Left = 380; Top = 360; Width = 760; Height = 540 } -WorkArea $wa
        $r.Left | Should -Be 912
        $r.Top | Should -Be 360
        $r.Width | Should -Be 760
        $r.Height | Should -Be 540
        ($r.Left + $r.Width) | Should -BeLessThan ($wa.X + $wa.Width)
    }

    It 'ignores tiny clamp corrections so a topmost pane does not oscillate' {
        Test-SlopPaneClampNeeded -Value 3 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeFalse
        Test-SlopPaneClampNeeded -Value -5 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeTrue
        Test-SlopPaneClampNeeded -Value 105 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeTrue
    }

    It 'never moves or resizes the pet while Extended chat is open' {
        $pet = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $r = Get-SlopPetRectDuringChat -PetRect $pet -ChatMode Extended
        $r.Left | Should -Be 412
        $r.Top | Should -Be 390
        $r.Width | Should -Be 484
        $r.Height | Should -Be 330
    }
}
```

Also change the existing `tests/slop-transparency-check.ps1` contract asserting `"uses the whole work area in Full mode"` to assert the large inset preset and mode-aware pet state. Add to that file static assertions that `Get-SlopChatDragGripRect` and `Test-SlopPaneClampNeeded` are called from `src/Slop.ChatWindow.ps1` and that `x:Name="ChatDragGrip"` exists in its XAML. Add to `tests/slop-shell-check.ps1` (existing hand-rolled `Assert-True` style) an assertion that `Add_LocationChanged` is wired in `src/Slop.ps1`.

Commit:

```powershell
git add tests/slop-pane-movement-check.ps1 tests/slop-transparency-check.ps1 tests/slop-shell-check.ps1
git commit -m "test: specify movable pane geometry and pet visibility"
```

Expected RED: the new module is absent, the changed transparency assertion fails, and the shell check misses the drag grip and clamp wiring.

### GREEN

Create `src/Slop.PaneMovement.ps1`:

```powershell
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
```

Add `Get-SlopChatDragGripRect` and `Get-SlopPinnedAwareChatRect` to `src/Slop.ChatWindow.ps1`. Change its `Full` branch to call `Get-SlopFullPaneRect`, and use `Get-SlopPinnedAwareChatRect` for chat open and mode switches so a pinned pet is never overlapped at those invariants. Preserve the existing clamping helpers. Wire `Set-SlopPetChatInteraction`, `Set-SlopChatWindowRect`, chat mode button, and chat close handlers in `src/Slop.ps1` to the new state functions. Add `x:Name="ChatDragGrip"` over `ChatChrome` with `Add_MouseLeftButtonDown` / `Add_MouseMove` / `Add_MouseLeftButtonUp` handlers that call `Get-SlopChatDragGripRect` and `Get-SlopMovedPaneRect`. Add an `Add_LocationChanged` guard that calls `Test-SlopPaneClampNeeded` before writing the corrected rect, with a 4px tolerance. Store the pet rect with `Get-SlopPetRectDuringChat` before entering `Full`; restore through `Get-SlopRestoredPetRect` when leaving `Full` or closing chat. The pet is never moved or resized.

Commit:

```powershell
git add src/Slop.PaneMovement.ps1 src/Slop.ChatWindow.ps1 src/Slop.ps1 tests/slop-transparency-check.ps1 tests/slop-shell-check.ps1
git commit -m "feat: add movable chat panes and full preset"
```

Expected GREEN: pane movement suite 8/8; existing shell and transparency suites pass; `git diff --check` clean.

## Task 2 — Capability toggles and deny-first profiles

### RED reproducer

Create `tests/slop-capability-toggle-check.ps1`:

```powershell
#requires -Version 7.6
Describe 'Slop capability toggles' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.CapabilityToggles.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeProfile.ps1')
    }

    It 'stores six named toggles, all off by default' {
        $defaults = Get-SlopDefaultCapabilityToggles
        @($defaults.Keys).Count | Should -Be 6
        foreach ($value in $defaults.Values) { $value | Should -BeFalse }
    }

    It 'rejects unknown toggles and non-boolean values' {
        (Test-SlopCapabilityToggles -Toggles @{ bogus = $true }).Ok | Should -BeFalse
        (Test-SlopCapabilityToggles -Toggles @{ workspaceFiles = 'yes' }).Ok | Should -BeFalse
    }

    It 'resolves companion, workspace, and power profiles from toggles' {
        Get-SlopCapabilityProfile -Toggles (Get-SlopDefaultCapabilityToggles) | Should -Be 'companion'
        $t = Get-SlopDefaultCapabilityToggles
        $t.workspaceFiles = $true
        Get-SlopCapabilityProfile -Toggles $t | Should -Be 'workspace'
        $t.shellCommands = $true
        Get-SlopCapabilityProfile -Toggles $t | Should -Be 'power'
    }

    It 'never removes hard denies from generated permissions' {
        $t = Get-SlopDefaultCapabilityToggles
        $t.externalFolders = $true
        $t.webAccess = $true
        $profile = Get-SlopCapabilityProfile -Toggles $t
        $cfg = New-SlopControlledConfig -Profile $profile -AgentId sloppy -Model beam-free -CapabilityToggles $t
        $json = $cfg | ConvertTo-Json -Depth 8 -Compress
        $json | Should -Match 'service\.json'
        $json | Should -Match '169\.254\.169\.254'
        $json | Should -Match 'file://\*'
    }

    It 'maps the six toggle keys to fixed OpenCode permission actions' {
        $map = Get-SlopCapabilityToggleMap
        $map.workspaceFiles | Should -Be 'read'
        $map.webAccess | Should -Be 'webfetch'
        $map.shellCommands | Should -Be 'shell'
        $map.skillsPlugins | Should -Be 'tool.use'
        $map.subagentsTasks | Should -Be 'subagent'
        $map.externalFolders | Should -Be 'external_directory'
    }

    It 'adds narrow allows only and never a wildcard rule' {
        $t = Get-SlopDefaultCapabilityToggles
        $t.workspaceFiles = $true
        $t.externalFolders = $true
        $cfg = New-SlopControlledConfig -Profile workspace -AgentId sloppy -Model beam-free -CapabilityToggles $t
        $allows = @($cfg.permissions | Where-Object { $_.effect -eq 'allow' })
        @($allows | Where-Object { $_.resource -eq '*' }).Count | Should -Be 0
        @($allows | Where-Object { $_.resource -like 'C:\Users\*' }).Count | Should -Be 0
    }

    It 'requires disclosure copy for web access and shell commands' {
        $disclosure = Get-SlopCapabilityDisclosure
        @($disclosure.Keys).Count | Should -Be 6
        $disclosure.webAccess | Should -Match 'beyond this PC'
        $disclosure.shellCommands | Should -Match 'change files'
    }
}
```

Also add config tests asserting that `New-SlopDefaultConfig` contains all-off `capabilityToggles`, v3 configs missing the key receive all-off defaults through `Read-SlopConfig`, and unknown or non-boolean toggles fail `Test-SlopConfig`.

Commit:

```powershell
git add tests/slop-capability-toggle-check.ps1 tests/slop-config-check.ps1 tests/slop-opencode-profile-check.ps1
git commit -m "test: specify default-off capability toggles"
```

Expected RED: new module and new config keys absent.

### GREEN

Create `src/Slop.CapabilityToggles.ps1`:

```powershell
# Pure capability toggle validation and profile resolution. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopCapabilityToggleMap {
    return @{
        workspaceFiles   = 'read'
        webAccess        = 'webfetch'
        shellCommands    = 'shell'
        skillsPlugins    = 'tool.use'
        subagentsTasks   = 'subagent'
        externalFolders  = 'external_directory'
    }
}

function Get-SlopDefaultCapabilityToggles {
    $result = @{}
    foreach ($key in (Get-SlopCapabilityToggleMap).Keys) { $result[$key] = $false }
    return $result
}

function Test-SlopCapabilityToggles {
    param([Parameter(Mandatory)][hashtable]$Toggles)
    $errors = [System.Collections.Generic.List[string]]::new()
    $valid = Get-SlopCapabilityToggleMap
    foreach ($key in $Toggles.Keys) {
        if (-not $valid.ContainsKey([string]$key)) {
            $errors.Add("unknown capability toggle: $key")
            continue
        }
        if ($Toggles[$key] -isnot [bool]) {
            $errors.Add("capability toggle must be boolean: $key")
        }
    }
    foreach ($key in $valid.Keys) {
        if (-not $Toggles.ContainsKey($key)) {
            $errors.Add("missing capability toggle: $key")
        }
    }
    return [pscustomobject]@{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}

function Get-SlopCapabilityProfile {
    param([Parameter(Mandatory)][hashtable]$Toggles)
    $check = Test-SlopCapabilityToggles -Toggles $Toggles
    if (-not $check.Ok) { return 'companion' }
    if ($Toggles.shellCommands) { return 'power' }
    if ($Toggles.workspaceFiles -or $Toggles.webAccess -or $Toggles.externalFolders) { return 'workspace' }
    return 'companion'
}

function Get-SlopCapabilityDisclosure {
    return @{
        workspaceFiles  = 'Can read files in the active workspace only.'
        webAccess       = 'Can fetch web content; requests can reach beyond this PC.'
        shellCommands   = 'Can run shell commands that may change files on this PC.'
        skillsPlugins   = 'Can load local skills and plugins from the active workspace.'
        subagentsTasks  = 'Can start bounded subagents and tasks for the current request.'
        externalFolders = 'Can read only folders you explicitly grant; no blanket home access.'
    }
}
```

Update `src/Slop.Config.ps1`:

- Dot-source `src/Slop.CapabilityToggles.ps1` near the top of `src/Slop.Config.ps1` (the pure toggle module has no dependency on config), so `Get-SlopDefaultCapabilityToggles` and `Test-SlopCapabilityToggles` resolve in the shell, config tests, and profile tests.
- Add `capabilityToggles = Get-SlopDefaultCapabilityToggles` to `New-SlopDefaultConfig`.
- In `Read-SlopConfig`, after the existing default-key copy loop, copy missing `capabilityToggles` keys and default every value to `$false`; never overwrite a present boolean.
- In `Test-SlopConfig`, call `Test-SlopCapabilityToggles` and reject unknown keys or non-boolean values. A missing key fails validation; only the reader repairs legacy v3 configs.
- Keep `$script:SlopConfigVersion = 3`.

Update `src/Slop.OpenCodeProfile.ps1`:

- Add optional `[hashtable]$CapabilityToggles` to `New-SlopControlledConfig`.
- Build capability-specific allow rules from `Get-SlopCapabilityToggleMap`; deny rules and hard-deny policies remain first and unchanged.
- Use `Get-SlopCapabilityProfile` when the caller does not pass an explicit profile.
- Do not add broad `~/Documents/*`, home-tree, or personal path allows. Enabled external folders remain subject to the existing explicit path grant rules and fail closed if no safe allow rule survives verification.
- Show `Get-SlopCapabilityDisclosure` copy beside the web and shell toggles in the Tools & Skills section; no toggle can be enabled without its disclosure visible.

Commit:

```powershell
git add src/Slop.CapabilityToggles.ps1 src/Slop.Config.ps1 src/Slop.OpenCodeProfile.ps1
git commit -m "feat: add default-off capability toggles"
```

Expected GREEN: capability suite 7/7; config and profile suites pass; effective-permission verification still fails closed.

## Task 3 — Control deck information architecture

### RED reproducer

Create `tests/slop-control-deck-check.ps1`:

```powershell
#requires -Version 7.6
Describe 'Slop control deck' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.ControlDeck.ps1')
        $script:ShellSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
        $script:ChatSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1') -Raw
    }

    It 'exposes exactly the six accepted sections' {
        $sections = Get-SlopControlDeckSections
        @($sections).Count | Should -Be 6
        @($sections).Name | Should -Be @('Overview','Settings','Data','Tools & Skills','Under the hood','Exit')
    }

    It 'declares the six capability toggles in the deck' {
        $toggles = Get-SlopControlDeckToggleIds
        @($toggles).Count | Should -Be 6
        $toggles | Should -Contain 'WorkspaceFilesToggle'
        $toggles | Should -Contain 'ExternalFoldersToggle'
    }

    It 'does not expose copy, clipboard, read-aloud, or raw permission JSON controls' {
        foreach ($src in @($script:ShellSrc, $script:ChatSrc)) {
            $src | Should -Not -Match 'CopyButton'
            $src | Should -Not -Match 'Clipboard'
            $src | Should -Not -Match 'ReadAloud'
            $src | Should -Not -Match 'PermissionJson'
        }
    }

    It 'uses the existing deletion scope contracts in Data' {
        . (Join-Path $PSScriptRoot '../src/Slop.Surfaces.ps1')
        $contract = Get-SlopDestinationContract -Name Privacy
        $contract.Actions | Should -Contain 'DeleteAllButton'
        $contract.Actions | Should -Contain 'DeleteOpenCodeButton'
        $script:ShellSrc | Should -Match 'Show-SlopConfirm[\s\S]{0,400}DeleteAllButton'
    }

    It 'shows copy-free Overview and read-only Under the hood state' {
        $script:ChatSrc | Should -Match 'x:Name="DeckOverviewText"'
        $script:ChatSrc | Should -Match 'x:Name="DeckConversationLengthText"'
        $script:ChatSrc | Should -Match 'x:Name="DeckUnderHoodText"[^>]*IsReadOnly="True"'
    }

    It 'opens by default in Full and reveals from Extended via a header button' {
        $script:ShellSrc | Should -Match 'x:Name="ControlDeckButton"'
        $script:ShellSrc | Should -Match '\$script:ChatDeckOpen\s*=\s*\$true'
        $script:ShellSrc | Should -Match "ChatMode -eq 'Full'[\s\S]{0,200}ChatDeckOpen"
    }

    It 'shows disclosure copy for web and shell toggles' {
        $script:ChatSrc | Should -Match 'x:Name="WebAccessDisclosureText"'
        $script:ChatSrc | Should -Match 'x:Name="ShellCommandsDisclosureText"'
        $script:ChatSrc | Should -Match 'beyond this PC'
        $script:ChatSrc | Should -Match 'change files'
    }

    It 'declares six section buttons and six toggle controls in chat XAML' {
        foreach ($name in @('DeckOverviewButton','DeckSettingsButton','DeckDataButton','DeckToolsButton','DeckUnderHoodButton','DeckExitButton',
                            'WorkspaceFilesToggle','WebAccessToggle','ShellCommandsToggle','SkillsPluginsToggle','SubagentsTasksToggle','ExternalFoldersToggle')) {
            $script:ChatSrc | Should -Match ([regex]::Escape('x:Name="' + $name + '"'))
        }
    }
}
```

Add to `tests/slop-shell-check.ps1` (existing `Assert-True` style, `$src` reads `src/Slop.ps1`) assertions that `ControlDeckButton`, `$script:ChatDeckOpen`, and `DeckStatusText` are wired in the shell.

Commit:

```powershell
git add tests/slop-control-deck-check.ps1 tests/slop-shell-check.ps1
git commit -m "test: specify control deck sections and controls"
```

Expected RED: new module absent; WPF deck, Overview/Under the hood controls, default-open state, and disclosure copy absent.

### GREEN

Create `src/Slop.ControlDeck.ps1`:

```powershell
# Pure control deck catalog. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopControlDeckSections {
    return @(
        @{ Name = 'Overview';        Key = 'overview' }
        @{ Name = 'Settings';        Key = 'settings' }
        @{ Name = 'Data';            Key = 'data' }
        @{ Name = 'Tools & Skills';  Key = 'tools' }
        @{ Name = 'Under the hood';  Key = 'underTheHood' }
        @{ Name = 'Exit';            Key = 'exit' }
    )
}

function Get-SlopControlDeckToggleIds {
    return @(
        'WorkspaceFilesToggle'
        'WebAccessToggle'
        'ShellCommandsToggle'
        'SkillsPluginsToggle'
        'SubagentsTasksToggle'
        'ExternalFoldersToggle'
    )
}
```

Add a `ControlDeckButton` beside `ChatModeButton` in `src/Slop.ps1`, and a `ChatDeckPanel` inside the chat XAML in `src/Slop.ChatWindow.ps1` with section buttons `DeckOverviewButton`, `DeckSettingsButton`, `DeckDataButton`, `DeckToolsButton`, `DeckUnderHoodButton`, `DeckExitButton` and the six named toggle controls from `Get-SlopControlDeckToggleIds`. The panel opens by default when `$script:ChatMode -eq 'Full'` and can be revealed in `Extended` via `ControlDeckButton`; `ChatDeckPanel` uses the existing dark fills and 2px `#8893A4BD` border with no change to window transparency. Preserve the existing named chat elements required by `tests/slop-shell-check.ps1`.

Wire the deck to existing Settings, Privacy, and Brain destinations instead of duplicating their logic. Overview shows `DeckOverviewText` (route, brain/model, session, signal count) and `DeckConversationLengthText` (copy-free conversation length). Under the hood shows `DeckUnderHoodText` as read-only effective route, endpoint, agent id, and motion/stream state. Data routes `DeleteAllButton` and `DeleteOpenCodeButton` through `src/Slop.Surfaces.ps1` scope contracts and `Show-SlopConfirm` before any action. Tools & Skills shows `WebAccessDisclosureText` and `ShellCommandsDisclosureText` from `Get-SlopCapabilityDisclosure`. Toggle saves call `Save-SlopSettings`; failed effective-permission verification keeps the previous config and shows the reason in `DeckStatusText`. Do not create a new top-level window.

Commit:

```powershell
git add src/Slop.ControlDeck.ps1 src/Slop.ChatWindow.ps1 src/Slop.ps1 tests/slop-shell-check.ps1 tests/slop-ia-check.ps1
git commit -m "feat: add six-section control deck"
```

Expected GREEN: deck suite 8/8; shell and IA suites pass; no prohibited control names appear.

## Task 4 — Selectable conversation text

### RED reproducer

Add to `tests/slop-shell-check.ps1` using its existing hand-rolled `Assert-True` style and its existing `$src` (raw `src/Slop.ps1`):

```powershell
Assert-True ($src -match '\[System\.Windows\.Controls\.TextBox\]::new\(\)') 'bubbles use read-only TextBox'
Assert-True ($src -match 'IsReadOnly\s*=\s*\$true') 'bubble text cannot be edited'
Assert-True ($src -match 'IsReadOnlyCaretVisible\s*=\s*\$true') 'bubble text is selectable'
Assert-True ($src -notmatch 'CopyButton|ReadAloud|Clipboard') 'no copy or read-aloud affordance'
Assert-True ($src -notmatch 'AssistantBubbleText\.Focus\(\)') 'bubble creation does not steal focus'
```

Commit:

```powershell
git add tests/slop-shell-check.ps1
git commit -m "test: specify selectable-only conversation text"
```

Expected RED: `Add-Bubble` still creates a `TextBlock` and no read-only `TextBox` exists.

### GREEN

In `Add-Bubble` in `src/Slop.ps1`, replace the conversation bubble `TextBlock` with a read-only `TextBox`:

```powershell
$textBox = [System.Windows.Controls.TextBox]::new()
$textBox.IsReadOnly = $true
$textBox.IsReadOnlyCaretVisible = $true
$textBox.Focusable = $true  # mouse selection works; no Focus() call is made
$textBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
$textBox.Background = [System.Windows.Media.Brushes]::Transparent
$textBox.BorderThickness = [System.Windows.Thickness]::new(0,0,0,0)
$textBox.Padding = [System.Windows.Thickness]::new(0,0,0,0)
$textBox.Foreground = $brush
$textBox.FontSize = 14
$textBox.Text = $Text
```

Keep the existing bubble border, margins, width, and alignment. `Focusable` stays `$true` for caret selection, but `Add-Bubble` never calls `.Focus()`, so creating a bubble does not steal focus. No Copy button, clipboard code, or TTS is added.

Commit:

```powershell
git add src/Slop.ps1
git commit -m "feat: make conversation text selectable"
```

Expected GREEN: shell suite passes; conversation text has no copy/read-aloud/clipboard affordance.

## Task 5 — Shutdown phrase and confirmed exit

### RED reproducer

Create `tests/slop-shutdown-phrase-check.ps1`:

```powershell
#requires -Version 7.6
Describe 'Slop confirmed shutdown' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Shutdown.ps1')
        $script:ShellSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
    }

    It 'normalizes the phrase with optional comma, case, and punctuation' {
        foreach ($phrase in @('Sloppy, shutdown','sloppy shutdown','SLOPPY SHUTDOWN.',' sloppy; shutdown! ')) {
            (Test-SlopShutdownPhrase -Text $phrase) | Should -BeTrue
        }
        Test-SlopShutdownPhrase -Text 'Sloppy, shut down' | Should -BeFalse
    }

    It 'asks once and accepts yes, y, or confirm' {
        $state = New-SlopShutdownConfirmation
        $first = Resolve-SlopShutdownInput -State $state -Text 'Sloppy, shutdown'
        $first.ConfirmationRequired | Should -BeTrue
        foreach ($answer in @('yes','Y','confirm')) {
            $r = Resolve-SlopShutdownInput -State $first.State -Text $answer
            $r.ShouldShutdown | Should -BeTrue
        }
    }

    It 'cancels on any other response and resumes normal handling' {
        $first = Resolve-SlopShutdownInput -State (New-SlopShutdownConfirmation) -Text 'Sloppy, shutdown'
        $r = Resolve-SlopShutdownInput -State $first.State -Text 'no'
        $r.ShouldShutdown | Should -BeFalse
        $r.Cancelled | Should -BeTrue
        $r.TextForNormalHandling | Should -Be 'no'
    }

    It 'shows the exact confirmation prompt' {
        Get-SlopShutdownPrompt | Should -Be 'Are you sure? Say or type yes.'
    }

    It 'composes clean teardown steps without killing processes' {
        $steps = @(Get-SlopShutdownTeardownSteps)
        $steps | Should -Be @('StopTimers','CancelStream','RejectPendingApprovals','DeleteOpenCodeSession','CloseChat','ShutdownApplication')
        $steps | Should -Not -Contain 'KillProcess'
        $script:ShellSrc | Should -Match 'Application\.Current\.Shutdown\(\)'
        $script:ShellSrc | Should -Not -Match 'Stop-Process'
    }
}
```

Commit:

```powershell
git add tests/slop-shutdown-phrase-check.ps1 tests/slop-shell-check.ps1
git commit -m "test: specify confirmed shutdown phrase"
```

Expected RED: new module absent and teardown wiring absent.

### GREEN

Create `src/Slop.Shutdown.ps1`:

```powershell
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
```

Wire the resolver into `$script:SlopSendAction`, `$script:SlopInputKeyDownAction`, and the voice text handoff. Voice text is transcribed to plain text before the resolver sees it. Sidebar Exit and tray Exit call the same resolver with the text `'Sloppy, shutdown'` so every entry point produces the same prompt, and write the returned state to `$script:SlopShutdownState`. Replace the current tray handler's `Stop-Process -Id $PID -Force` at `src/Slop.ps1` line 984 with that resolver call. On cancel, reset `$script:SlopShutdownState` and pass `TextForNormalHandling` to the normal handler; on confirmation, show `Get-SlopShutdownPrompt`, then follow `Get-SlopShutdownTeardownSteps`: reuse the existing `$window.Add_Closed` cleanup for timers, stream cancellation, pending approvals, OpenCode session deletion, and chat close, then call `[System.Windows.Application]::Current.Shutdown()`. Do not kill processes or skip session cleanup.

Commit:

```powershell
git add src/Slop.Shutdown.ps1 src/Slop.ps1
git commit -m "feat: add confirmed shutdown phrase"
```

Expected GREEN: shutdown suite 5/5; shell suite still passes; no direct process kill introduced.

## Task 6 — Tour and documentation refresh

### RED reproducer

Source edits shift anchors. Update `tests/slop-tour-check.ps1` and `.tours/architect-slop-architecture.tour` together after all source edits, preserving 18 steps and the required anchored fragments listed in the current tour test. Add steps only by replacing included sections, not by deleting required coverage.

Commit:

```powershell
git add tests/slop-tour-check.ps1 .tours/architect-slop-architecture.tour
git commit -m "test: anchor tour to new pane and deck code"
```

Expected RED: current anchors are stale after Tasks 1–5.

### GREEN

Recompute every `file` and `line` from the working tree with a temp probe that reads each expected fragment and writes the exact current line. Keep all 18 steps anchored to real source. Update README or architecture docs only where they describe Full mode or capability behavior:

- Full is a large inset draggable preset, not work-area-filling.
- The pea is visible in Extended and hidden in Full.
- All six capability toggles are off by default.
- Conversation text is selectable only.
- `Sloppy, shutdown` requires a typed or spoken yes.

Commit:

```powershell
git add .tours/architect-slop-architecture.tour README.md docs/architecture.md
git commit -m "docs: refresh tour and pane behavior documentation"
```

Expected GREEN: tour 38/38; all anchors resolve.

## Validation before execution approval

After writing this plan, validate it without touching product code:

1. Parse every fenced PowerShell block with `[System.Management.Automation.Language.Parser]::ParseInput`; expect 0 errors.
2. Temp-probe the pure pane, toggle, and shutdown functions from this plan; expect all RED assertions to fail before GREEN source and all GREEN values to match.
3. Verify each cited anchor against the working tree: listed function and XAML names exist at the listed files.
4. Scan the plan for unfinished-work placeholder tokens and a standalone ellipsis, plus machine-specific paths; expect 0. A git range such as `origin/main...HEAD` is not a placeholder.
5. Check `Test-SlopEffectivePermissions` contracts continue to fail closed with broad grants.
6. Confirm no plan step deletes files, changes `data/`, pushes, tags, deploys, or changes visibility.

## Final execution gates

Run after the final source commit:

```powershell
pwsh -NoProfile -File .\tests\slop-pane-movement-check.ps1
pwsh -NoProfile -File .\tests\slop-capability-toggle-check.ps1
pwsh -NoProfile -File .\tests\slop-control-deck-check.ps1
pwsh -NoProfile -File .\tests\slop-shutdown-phrase-check.ps1
pwsh -NoProfile -File .\tests\slop-transparency-check.ps1
pwsh -NoProfile -File .\tests\slop-shell-check.ps1
pwsh -NoProfile -File .\tests\slop-config-check.ps1
pwsh -NoProfile -File .\tests\slop-opencode-profile-check.ps1
pwsh -NoProfile -File .\tests\slop-ia-check.ps1
pwsh -NoProfile -File .\tests\slop-tour-check.ps1
~/.agents/scripts/verify.ps1
~/.agents/scripts/review.ps1
git diff --check
git status --short
git rev-list --left-right --count origin/main...HEAD
```

Expected:

- Each focused suite: `Failed 0`.
- Canonical verify: explicit `Failed: 0` and exit code 0.
- Review: exit 0.
- `git diff --check`: exit 0.
- `git status --short`: empty after the final commit.
- Divergence: `0 N`, where `N` is the local commit count; nothing pushed.

After the static gates, restart with `tools/slop-control.ps1` and ask the user to visually confirm the three scenes (pea-only, Extended with visible pea, Full with hidden pea and deck), both drag gestures, selectable text, capability toggles, and spoken/typed shutdown confirmation. The agent records the result but makes no live visual claim.

Not claimed by this plan: live appearance, live drag feel, live voice confirmation, or runtime permission behavior. The user verifies those after execution.
