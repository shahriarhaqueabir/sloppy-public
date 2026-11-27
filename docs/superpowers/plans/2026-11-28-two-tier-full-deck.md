# Two-tier model picker and full-height no-scroll deck implementation plan

Date: 2026-11-28

## Source of truth

This plan implements the approved design in `docs/superpowers/specs/2026-11-28-two-tier-full-deck-design.md`. It does not reopen product decisions. Product-code execution stays gated until the user explicitly approves this plan inline.

## Operating rules

- Work inline on `main`. Do not dispatch subagents.
- Every product change is RED then GREEN with explicit paths. Never use `git add -A`.
- Do not push, tag, release, deploy, force-push, change visibility, or modify `data/`.
- `startslop` and `stopslop` must keep working against this repository.
- No hardcoded user path in product code. Tier 1 assets stay in the app root. Tier 2 service credentials stay in the OpenCode service config under the user profile or XDG config.
- Never put raw catalog payload, response headers, org identifiers, credentials, or service passwords in UI, logs, tests, or docs.
- Do not claim live visual, voice, or live process-exit behavior. The user confirms those separately.
- Recompute CodeTour anchors after any source insertion. Do not assume old line numbers.

## Recon anchors verified before writing this plan

These are recon facts, not immutable execution anchors. Recompute all file/line anchors before each edit.

- `src/Slop.Config.ps1:21` defines brains; `:108` defines brain order; `:110-117` defines static model options; `:119-126` defines the numeric tier compatibility wrapper; `:347-404` defines `Set-SlopConfigBrain`.
- `src/Slop.ControlDeck.ps1:26-41` caps deck body height at 220 px; `:103-135` builds model edit arguments.
- `src/Slop.ChatWindow.ps1:100-106` defines four rows; `:137` starts `ChatDeckPanel` in row 1; `:176` pins `DeckBody Height="220"`; `:183` adds the inner `ScrollViewer`; `:225-226` defines `DeckModelBox`.
- `src/Slop.ps1:637-667` captures chat controls; `:669-696` restores them; `:698-735` fills deck state; `:772-810` saves the model; `:812-869` switches sections and updates visibility; `:1163-1200` sets pane rect and mode; `:1209-1280` wires chat-window handlers; `:1562-1569` resolves the effective loopback base URL; `:1772-1785` fills main Settings brain/model controls; `:1949-1956` updates the main Settings model list.
- `src/Slop.OpenCode.ps1:145-168` builds the Basic auth header from the loopback service URL and service config path.
- `src/Slop.Route.ps1:129` is the established auth-header call pattern.
- `tests/slop-control-deck-check.ps1:65-70` asserts the capped-height contract; `:149-166` asserts section switching does not touch chat visibility; `:168-179` asserts save wiring.
- `tests/slop-transparency-check.ps1:177-207` asserts the four-row XAML, fixed deck height, and current model controls.
- `tests/slop-config-check.ps1:363-377` asserts current brain/model defaults.
- `tests/slop-onboarding-check.ps1:102-105` asserts the static two-model prefill.
- `tests/slop-tour-check.ps1:16-70` guards 18 tour steps and anchored fragments.
- `tests/Slop.Tests.ps1:11-13` aggregates every `*-check.ps1` file, so a new suite is discovered automatically.

## Target contracts

### Tier contracts in `src/Slop.Config.ps1`

Add these pure functions beside `Resolve-SlopTier`. Keep `Resolve-SlopTier` unchanged for existing 1/2/0 callers.

```powershell
function Get-SlopTierCatalog {
    $defaults = New-SlopDefaultConfig
    return @(
        @{ Id = 'tier-1'; Label = 'Tier 1 - Local LLM'; Brain = 'builtin'; DefaultModel = [string]$defaults.localModelName }
        @{ Id = 'tier-2'; Label = 'Tier 2 - OpenCode'; Brain = 'opencode'; DefaultModel = 'big-pickle' }
    )
}

function Resolve-SlopTierFromConfig {
    param([AllowNull()][hashtable]$Config)
    if ($null -eq $Config) { return '' }
    switch ([string]$Config.brain) {
        'builtin'  { return 'tier-1' }
        'opencode' { return 'tier-2' }
        default    { return '' }
    }
}

function Get-SlopTierDefaultModel {
    param([Parameter(Mandatory)][ValidateSet('tier-1','tier-2')][string]$TierId)
    if ($TierId -eq 'tier-1') { return [string](New-SlopDefaultConfig).localModelName }
    return 'big-pickle'
}

function Set-SlopTierConfig {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][ValidateSet('tier-1','tier-2')][string]$TierId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Model,
        [string]$BaseUrl = (New-SlopDefaultConfig).openCodeBaseUrl
    )

    $defaults = New-SlopDefaultConfig
    $isLocal = ($TierId -eq 'tier-1')
    $brain = if ($isLocal) { 'builtin' } else { 'opencode' }
    $modelValue = if ($isLocal) { [string]$defaults.localModelName } else { ([string]$Model).Trim() }

    if (-not $isLocal -and [string]::IsNullOrWhiteSpace($modelValue)) {
        return @{ Ok = $false; Config = $Config; Errors = @('Model is required.') }
    }
    if (-not $isLocal -and -not (Test-SlopLoopbackHttpUrl -Url $BaseUrl)) {
        return @{ Ok = $false; Config = $Config; Errors = @('OpenCode base URL must be loopback http.') }
    }

    $result = Set-SlopConfigBrain -Config $Config `
        -Brain $brain `
        -Provider $(if ($isLocal) { '' } else { 'opencode' }) `
        -ProviderLocality $(if ($isLocal) { '' } else { [string]$Config.providerLocality }) `
        -EndpointUrl '' `
        -Model $modelValue `
        -AgentId $(if ($isLocal) { '' } else { 'sloppy' }) `
        -CapabilityProfile 'companion'
    if (-not $result.Ok) { return $result }

    $candidate = $result.Config
    if ([string]::IsNullOrWhiteSpace([string]$candidate.localModelName)) { $candidate.localModelName = [string]$defaults.localModelName }
    if ([string]::IsNullOrWhiteSpace([string]$candidate.localModelFile)) { $candidate.localModelFile = [string]$defaults.localModelFile }
    if (-not $isLocal) { $candidate.openCodeBaseUrl = $BaseUrl.Trim().TrimEnd('/') }
    return @{ Ok = $true; Config = $candidate; Errors = @() }
}
```

Behavior notes:

- Tier 1 forces `brain=builtin`, leaves the bundled `localModelFile` in place, restores the default app-root relative path when absent, and makes no network call.
- Tier 2 forces `brain=opencode`, provider `opencode`, agent `sloppy`, the effective loopback base URL, and the selected model.
- `custom` remains valid in config and runtime. `Resolve-SlopTierFromConfig` returns an empty string for it, so the UI can show no selection.
- No new config schema version and no new validation rule. `Set-SlopTierConfig` delegates validation to `Set-SlopConfigBrain`.

### Model catalog module `src/Slop.ModelCatalog.ps1`

Create a headless module with no WPF dependency. The shell dot-sources `Slop.Config.ps1` before this module so `Test-SlopLoopbackHttpUrl` is available.

```powershell
function Get-SlopFreeChatModels {
    param([Parameter(Mandatory)][AllowNull()]$CatalogData)

    $items = @()
    if ($null -ne $CatalogData -and $CatalogData.PSObject.Properties['data']) {
        $items = @($CatalogData.data)
    } elseif ($null -ne $CatalogData -and $CatalogData -is [System.Collections.IEnumerable] -and $CatalogData -isnot [string]) {
        $items = @($CatalogData)
    }

    $byId = [ordered]@{}
    $preferred = @{}
    foreach ($item in $items) {
        if ([string]$item.type -cne 'chat') { continue }
        if ($null -ne $item.enabled -and [bool]$item.enabled -eq $false) { continue }
        if ([string]$item.status -cne 'active') { continue }

        $costEntries = @()
        if ($null -ne $item.cost) { $costEntries = @($item.cost) }
        if ($costEntries.Count -eq 0) { continue }
        $free = $true
        foreach ($entry in $costEntries) {
            $inputCost = 0.0
            $outputCost = 0.0
            if ($null -ne $entry) {
                [void][double]::TryParse([string]$entry.input, [ref]$inputCost)
                [void][double]::TryParse([string]$entry.output, [ref]$outputCost)
            }
            if ($inputCost -ne 0 -or $outputCost -ne 0) { $free = $false; break }
        }
        if (-not $free) { continue }

        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
        $isPreferred = ([string]$item.providerID -ceq 'opencode')

        if ($byId.Contains($id)) {
            if ($isPreferred -and -not [bool]$preferred[$id]) {
                $byId[$id] = @{ Id = $id; Name = $name }
                $preferred[$id] = $true
            }
            continue
        }
        $byId[$id] = @{ Id = $id; Name = $name }
        $preferred[$id] = $isPreferred
    }

    $all = @($byId.Values)
    $pinned = @($all | Where-Object { $_.Id -ceq 'big-pickle' })
    $rest = @($all | Where-Object { $_.Id -cne 'big-pickle' } | Sort-Object -Property Name -CaseSensitive)
    return @($pinned + $rest)
}

function Get-SlopModelCatalogResult {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [hashtable]$Headers
    )

    if (-not (Test-SlopLoopbackHttpUrl -Url $BaseUrl)) {
        return @{ Ok = $false; Models = @(); Error = 'OpenCode service URL must be loopback.' }
    }
    try {
        $uri = $BaseUrl.Trim().TrimEnd('/') + '/api/model'
        $response = Invoke-WebRequest -Uri $uri -Headers $Headers -UseBasicParsing -TimeoutSec 8
        if ([int]$response.StatusCode -ne 200) {
            return @{ Ok = $false; Models = @(); Error = 'OpenCode model catalog could not be read.' }
        }
        $payload = $response.Content | ConvertFrom-Json
        $models = @(Get-SlopFreeChatModels -CatalogData $payload)
        return @{ Ok = $true; Models = $models; Error = '' }
    } catch {
        return @{ Ok = $false; Models = @(); Error = 'OpenCode model catalog could not be read.' }
    }
}

function Get-SlopModelCatalogStatusText {
    param([Parameter(Mandatory)][hashtable]$Result)
    if (-not [bool]$Result.Ok) { return [string]$Result.Error }
    $count = @($Result.Models).Count
    if ($count -eq 0) { return 'No free chat models returned.' }
    return "$count free chat models available."
}
```

Privacy contract:

- `Get-SlopModelCatalogResult` returns exactly `Ok`, `Models`, and `Error`.
- `Models` contains only `Id` and `Name` hashtables.
- Catch blocks return fixed copy. No exception text, header, payload, URL query, or org identifier is returned.
- Fetch uses only the local OpenCode service. Catalog entries may point at remote inference URLs, but Sloppy never connects to those URLs.

### Deck layout helpers in `src/Slop.ControlDeck.ps1`

Replace the capped-height helper and add one new helper.

```powershell
function Get-SlopDeckBodyHeight {
    param(
        [Parameter(Mandatory)][double]$WindowHeight,
        [Parameter(Mandatory)][bool]$DeckOpen,
        [double]$FixedHeight = 88.0,
        [double]$OuterMargin = 16.0
    )
    if (-not $DeckOpen) { return 0 }
    $height = $WindowHeight - $FixedHeight - $OuterMargin
    if ($height -le 0) { return 0 }
    return [int][Math]::Floor($height)
}

function Get-SlopDeckExpandedWindowHeight {
    param(
        [Parameter(Mandatory)][double]$WorkAreaHeight,
        [Parameter(Mandatory)][double]$CurrentHeight,
        [double]$PreferredHeight = 620.0
    )
    $wanted = [Math]::Max($PreferredHeight, $CurrentHeight)
    return [int][Math]::Floor([Math]::Min($WorkAreaHeight, $wanted))
}
```

Behavior notes:

- No 220 px body cap and no transcript/composer minima.
- Expanded height never shrinks the current window and never exceeds the work area.
- Section content is sized to the deck body. The user can manually resize when the work area clamps the preferred height.

## Task 1: RED tier contracts

Commit `tests/slop-config-check.ps1` only.

Add assertions that fail against current source:

- `Get-SlopTierCatalog` returns exactly two ordered entries with ids `tier-1`, `tier-2`, labels containing `Local LLM` and `OpenCode`, and default models from the config defaults and `big-pickle`.
- `Resolve-SlopTierFromConfig` maps `builtin` to `tier-1`, `opencode` to `tier-2`, `custom` and unknown values to empty string, and null to empty string.
- `Get-SlopTierDefaultModel` returns the bundled local model name and `big-pickle`.
- `Resolve-SlopTier -Brain 'builtin'` still returns `1`, `opencode` returns `2`, and `custom` returns `0`.
- `Set-SlopTierConfig -TierId 'tier-1'` returns `brain=builtin`, preserves or restores `localModelFile`, uses the app-root relative bundled path, and does not create a network endpoint.
- `Set-SlopTierConfig -TierId 'tier-2' -Model 'big-pickle'` returns `brain=opencode`, `provider=opencode`, `agentId=sloppy`, `model=big-pickle`, and a loopback `openCodeBaseUrl`.
- A non-loopback Tier 2 base URL fails with no config mutation.
- An empty Tier 2 model fails with no config mutation.
- The source still contains no hardcoded user path.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-config-check.ps1 -Output Detailed
```

Expected: the new assertions fail because the tier functions are absent.

## Task 2: GREEN tier contracts

Commit `src/Slop.Config.ps1` only.

- Add the four functions from the target contract section.
- Keep `Resolve-SlopTier` unchanged.
- Keep `Get-SlopBrainOrder`, `Get-SlopBrainModelOptions`, and all existing validation behavior unchanged.
- Do not touch `data/`.

Run the same focused suite. Expected: all assertions pass. Then commit the RED test and GREEN source as separate explicit-path commits.

## Task 3: RED model catalog

Commit `tests/slop-model-catalog-check.ps1` only.

Create a new Pester suite that dot-sources `src/Slop.Config.ps1` and then `src/Slop.ModelCatalog.ps1` in `BeforeAll`, with these assertions:

- Fixture object with a `data` array containing chat, non-chat, disabled, inactive, paid, duplicate, and `big-pickle` entries.
- `Get-SlopFreeChatModels` keeps only active enabled zero-cost chat entries.
- Duplicate ids collapse to one entry and prefer the entry with `providerID='opencode'`.
- `big-pickle` is first; remaining entries are sorted by name.
- Every returned object exposes only `Id` and `Name`.
- Passing a bare array works as well as an object with `data`.
- `Get-SlopModelCatalogResult -BaseUrl 'http://example.test'` fails with `Ok=$false`, empty `Models`, and fixed error copy, without a network call.
- A fake result with `Ok=$false` produces short status copy; a fake result with zero models produces the empty-list copy; a fake result with models produces a count copy.
- The new module source contains no raw header name other than the auth header call in the shell, no org identifier, and no hardcoded user path.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-model-catalog-check.ps1 -Output Detailed
```

Expected: discovery or function-not-found failures.

## Task 4: GREEN model catalog

Commit `src/Slop.ModelCatalog.ps1` only.

- Add the module from the target contract section.
- Keep it dependency-free except for the loopback validator supplied by `Slop.Config.ps1`.
- Never return raw payload, exception text, response headers, org identifiers, or credentials.
- Do not add a catalog fetch at module load time.

Run the focused suite. Expected: all assertions pass. `tests/Slop.Tests.ps1` discovers the new suite automatically; confirm the aggregate count rises by the new test count.

## Task 5: RED deck layout helpers

Commit `tests/slop-control-deck-check.ps1` only.

Replace the capped-height assertions with:

- `Get-SlopDeckBodyHeight -WindowHeight 760 -DeckOpen $true` returns `656`.
- `Get-SlopDeckBodyHeight -WindowHeight 1200 -DeckOpen $true` returns `1096`.
- `Get-SlopDeckBodyHeight -WindowHeight 760 -DeckOpen $false` returns `0`.
- `Get-SlopDeckBodyHeight -WindowHeight 80 -DeckOpen $true` returns `0`.
- `Get-SlopDeckExpandedWindowHeight -WorkAreaHeight 1200 -CurrentHeight 700` returns `700`.
- `Get-SlopDeckExpandedWindowHeight -WorkAreaHeight 1200 -CurrentHeight 400` returns `620`.
- `Get-SlopDeckExpandedWindowHeight -WorkAreaHeight 500 -CurrentHeight 900` returns `500`.
- The existing static visibility and handler assertions remain, with the model-save assertion updated to require `Set-SlopTierConfig` in `Save-SlopDeckModel`.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-control-deck-check.ps1 -Output Detailed
```

Expected: the height assertions and save-wiring assertion fail.

## Task 6: GREEN deck layout helpers

Commit `src/Slop.ControlDeck.ps1` only.

- Replace `Get-SlopDeckBodyHeight` with the uncapped version.
- Add `Get-SlopDeckExpandedWindowHeight`.
- Leave section catalog, toggle ids, settings snapshot, voice edit, and model edit argument helpers intact. The shell will stop using the model edit helper, but keeping it avoids unrelated churn.

Run the focused suite. Expected: all assertions pass.

## Task 7: RED XAML restructure

Commit `tests/slop-transparency-check.ps1` only.

Update the layout assertions:

- `ChatDeckPanel` includes `Grid.RowSpan="3"` while remaining `Grid.Row="1"`.
- `DeckBody` no longer has `Height="220"`.
- No `ScrollViewer` appears between `DeckBody` and the deck section stack panels.
- The chat transcript and composer rows still exist for the collapsed state.
- The deck Settings section exposes `DeckTierCombo`, `DeckModelCombo`, `DeckModelRefreshButton`, `DeckModelRouteText`, and `DeckModelSaveButton`.
- `DeckModelBox` is absent.
- The main Settings model controls remain untouched.
- Readable fill and button assertions remain green.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-transparency-check.ps1 -Output Detailed
```

Expected: the XAML structure assertions fail.

## Task 8: GREEN XAML restructure

Commit `src/Slop.ChatWindow.ps1` only.

- Change `ChatDeckPanel` to `Grid.Row="1" Grid.RowSpan="3"`.
- Remove `Height="220"` from `DeckBody` and keep it stretch-filled.
- Remove the inner `ScrollViewer`; place deck sections directly in the body grid with the status text row retained.
- Replace the free-text `DeckModelBox` with a two-tier `DeckTierCombo`, a `DeckModelCombo`, a `DeckModelRefreshButton`, the existing `DeckModelRouteText`, and the existing `DeckModelSaveButton`.
- Tighten Settings card margins enough for the new controls to fit at full height.
- Do not add a system material, a native window chrome, or any credential/path text.
- Parse the XAML with `[System.Windows.Markup.XamlReader]::Parse` inside the existing test before claiming GREEN.

Run the focused suite. Expected: all assertions pass.

## Task 9: RED shell tier and catalog wiring

Commit `tests/slop-control-deck-check.ps1` only.

Add static source assertions against `src/Slop.ps1`:

- The shell dot-sources `Slop.ModelCatalog.ps1`.
- `Use-SlopChatControls` captures `DeckTierCombo`, `DeckModelCombo`, and `DeckModelRefreshButton`.
- `Restore-SlopMainChatControls` nulls those controls.
- `Update-SlopDeckSettingsUi` selects the tier from `Resolve-SlopTierFromConfig`, fills the model combo from the cached catalog, and preserves a saved model absent from the current catalog.
- `Save-SlopDeckModel` calls `Set-SlopTierConfig`, writes config, refreshes route text, and never calls `Get-SlopDeckModelEditArguments`.
- Tier 1 refresh path contains no `Invoke-WebRequest` and no catalog call.
- Tier 2 refresh path calls `Get-SlopEffectiveOpenCodeBaseUrl`, `New-SlopOpenCodeAuthHeader`, and `Get-SlopModelCatalogResult` with `ServiceConfigPath` from config.
- Result copy comes from `Get-SlopModelCatalogStatusText`.
- A missing auth header, non-200 response, malformed payload, or exception is caught before the shell writes status; the saved model and config are untouched.
- An unavailable config results in no tier selection and a short Save status; the shell does not throw an unhandled exception.
- A config write failure surfaces a short status message while the in-memory config remains valid.
- Tier 1 disables `DeckModelCombo` and shows the bundled model as read-only text; Tier 2 enables it and fetches when nothing is cached.
- No shell source line exposes response payloads, request headers, service-specific identifiers, or a credential value in status text.
- The `BrainTypeCombo` handler in main Settings keeps using `Get-SlopBrainModelOptions`; only the deck model card changes.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-control-deck-check.ps1 -Output Detailed
```

Expected: the new shell assertions fail.

## Task 10: GREEN shell tier and catalog wiring

Commit `src/Slop.ps1` only.

- Add session state for the catalog result, expanded-height restore state, and pane-mode restore state near the existing chat state variables.
- Add shell functions:
  - `Set-SlopDeckStatus` stays the single status writer.
  - `Get-SlopDeckTierIdFromUi` maps the selected tier label to `tier-1` or `tier-2`.
  - `Update-SlopDeckModelUi` fills tier labels from `Get-SlopTierCatalog`, selects from config, fills model items from the cached catalog, preselects the saved model, adds the saved model when absent, disables the combo for Tier 1, and writes a short note for `custom`.
  - `Invoke-SlopModelCatalogRefresh` returns immediately for Tier 1; for Tier 2 it resolves the base URL, builds auth headers via `New-SlopOpenCodeAuthHeader -ServiceConfigPath $Config.serviceConfigPath -BaseUrl $baseUrl`, calls `Get-SlopModelCatalogResult`, caches the result, updates the combo, and sets status copy from `Get-SlopModelCatalogStatusText`.
  - `Save-SlopDeckModel` uses `Set-SlopTierConfig` and the existing config write/update sequence.
- Wire `DeckTierCombo` selection, `DeckModelRefreshButton`, and `DeckModelSaveButton` in `Initialize-SlopChatControlHandlers`.
- Call `Invoke-SlopModelCatalogRefresh` when the Model section is first opened with Tier 2 selected, when Tier 2 is newly selected with an empty cache, and on explicit Refresh only.
- Tier 1 disables `DeckModelCombo` and shows the bundled model as read-only text. Tier 2 enables the combo.
- Guard `New-SlopOpenCodeAuthHeader` failures and catalog exceptions so status is short, saved config is unchanged, and no exception detail escapes.
- If `SlopConfigResult` is unavailable, leave the tier combo unselected and show a short Save status instead of throwing.
- Wrap config writes so a failure updates status while the in-memory config remains usable.
- A failed or offline fetch leaves the saved model untouched and selected.
- No raw payload or header escapes the module boundary.

Run the focused suite. Expected: all assertions pass.

## Task 11: RED full-height expand/collapse behavior

Commit `tests/slop-control-deck-check.ps1` only.

Add assertions:

- `Update-SlopControlDeckVisibility` sets `ChatScroll.Visibility` and `ChatInputChrome.Visibility` to collapsed when deck open and visible when closed.
- Section switching still does not write either chat visibility property.
- A shared `Set-SlopDeckExpandedState` function exists and both the header deck button and strip chevron call it.
- Opening records the exact current height and pane mode, calls `Get-SlopDeckExpandedWindowHeight`, and applies the result.
- Collapsing restores the recorded mode and exact recorded height before clearing restore state.
- `Set-SlopChatWindowRect` clears deck restore state on an explicit pane mode change.
- The deck strip stays visible in both states.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-control-deck-check.ps1 -Output Detailed
```

Expected: the new visibility and restore assertions fail.

## Task 12: GREEN full-height expand/collapse behavior

Commit `src/Slop.ps1` only.

- Add `Set-SlopDeckExpandedState -Open $bool`.
- On open: store current `Height` and `ChatMode`, compute expanded height from `SystemParameters.WorkArea.Height` and the current height, set window height, set `ChatDeckOpen=$true`, then update visibility.
- On close: restore the recorded pane mode through `Set-SlopChatWindowRect` when it changed, restore the exact recorded height, set `ChatDeckOpen=$false`, clear restore state, then update visibility.
- Have `Update-SlopControlDeckVisibility` hide `ChatScroll` and `ChatInputChrome` only when the deck body is open and show them when closed. Do not change the deck strip.
- Replace the header deck button and strip chevron handlers with calls to the shared state function.
- Clear restore state in `Set-SlopChatWindowRect` for explicit mode changes so mode and height owners stay unambiguous.
- Keep `Add_Closed` cleanup and shutdown teardown intact.

Run the focused suite. Expected: all assertions pass.

## Task 13: RED onboarding and docs alignment

Commit `tests/slop-onboarding-check.ps1` only.

- Replace the static two-model prefill assertion with a Tier 2 default assertion using `Get-SlopTierDefaultModel`.
- Assert onboarding still contains no paid-provider controls or price tier field.
- Assert architecture text names exactly two UI tiers, maps Tier 1 to the bundled app-root GGUF and local llama.cpp loopback, maps Tier 2 to the loopback OpenCode service and `sloppy` agent, states that Tier 2 defaults to `big-pickle`, and states that the expanded deck hides chat so a whole section fits without an inner scrollbar.
- Assert docs contain no raw catalog payload, org identifier, credential, or hardcoded user path.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-onboarding-check.ps1 -Output Detailed
```

Expected: the prefill assertion fails until the GREEN commit.

## Task 14: GREEN onboarding and docs alignment

Commit `src/Slop.Onboarding.ps1` and `docs/architecture.md`. The tier default helper already exists from Task 2; do not edit `src/Slop.Config.ps1` again.

GREEN path:

- Onboarding prefill at `src/Slop.Onboarding.ps1:254` reads `Get-SlopTierDefaultModel -TierId 'tier-2'` while still preferring a saved config model.
- Architecture current-state text is updated with the two-tier map, live catalog filter, and full-height deck decision.
- The old static `Get-SlopBrainModelOptions` behavior remains for main Settings compatibility.

Run the focused suite. Expected: all assertions pass.

## Task 15: RED tour and brand refresh

Commit `tests/slop-tour-check.ps1` and `tests/slop-brand-check.ps1` only if their expectations must change.

- Recompute all 18 CodeTour file/line anchors from source fragments after the shell insertions. Update `.tours/architect-slop-architecture.tour` only after the fragment check proves each line.
- Update the tour title or description only where it still claims the old capped deck or static two-model list.
- Update the brand baseline generator expectations only for intentional copy changes. Keep the ratchet behavior: new unexplained findings fail.
- Add a static assertion that no raw catalog payload keys, request-header names, or service-specific identifiers appear in UI-facing source or docs.

Run:

```powershell
Invoke-Pester -Path .\tests\slop-tour-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-brand-check.ps1 -Output Detailed
```

Expected: stale anchors fail until recomputed; brand gate fails until the baseline is regenerated from intentional copy.

## Task 16: GREEN tour and brand refresh

Commit `.tours/architect-slop-architecture.tour`, `tests/slop-brand-baseline.json`, and any intentional test expectation file in one explicit-path commit.

- Recompute anchors from actual source fragments, not from old line numbers.
- Regenerate `tests/slop-brand-baseline.json` from the current source.
- Grep the source to prove the old capped-deck and static-model copy is gone rather than trusting the generated artifact blindly.
- Keep the tour at 18 steps.

Run both focused suites. Expected: all assertions pass.

## Final verification

Run these from the repository root, in order, after the final commit:

```powershell
Invoke-Pester -Path .\tests\slop-config-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-model-catalog-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-control-deck-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-transparency-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-onboarding-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-tour-check.ps1 -Output Detailed
Invoke-Pester -Path .\tests\slop-brand-check.ps1 -Output Detailed
& ~/.agents/scripts/verify.ps1
git diff --check
git status --short
git rev-list --left-right --count origin/main...HEAD
```

Acceptance for the verify gate is an explicit `Failed: 0`, not only a wrapper summary line. Record exact pass counts.

Also run the review gate and a repository hygiene scan:

```powershell
& ~/.agents/scripts/review.ps1
git grep -n -I -E 'C:\\Users\\[A-Za-z0-9._-]+|x-[a-z]+-[a-z-]+|settings\.[A-Za-z]+' -- src tests docs .tours
```

The hygiene command should find no user-specific path and no raw catalog field name. A match in a test fixture is still a failure for org id and credentials; catalog field names are allowed only inside the pure module fixture-building test, never in UI-facing source or docs.

## Final self-review checklist

Before presenting completion, answer each honestly:

1. Did the two-tier picker show exactly two entries, with no `custom` UI entry?
2. Did Tier 1 preserve the bundled app-root GGUF and make no network call?
3. Did Tier 2 default to `big-pickle` and use the live filtered local OpenCode catalog?
4. Did a failed fetch leave the saved model untouched?
5. Did the expanded deck remove the inner scrollbar and hide chat only while open?
6. Did collapse restore the exact prior height and mode?
7. Did no raw payload, header, org id, credential, or hardcoded user path enter UI, logs, tests, or docs?
8. Did focused suites, canonical verify, review, diff check, tour, brand, status, and divergence all pass with exact evidence?
9. Did the agent avoid any live visual, voice, or process-exit claim?

## Execution approval gate

After this plan is committed, stop. Ask the user for explicit approval to execute inline. Do not edit product code before that approval.
