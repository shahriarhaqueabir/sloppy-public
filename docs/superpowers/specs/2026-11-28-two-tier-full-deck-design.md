# Two-tier model picker and full-height no-scroll deck design

Date: 2026-11-28

## Context

The user asked what happened to the model tiers and requested three things:

1. The picker should offer exactly two options: Tier 1 and Tier 2.
2. Tier 1 is the local LLM; Tier 2 is OpenCode with `big-pickle` as the default and the other verified free chat models available.
3. Opening the control deck should show the whole section with no scrolling.

The user explicitly required that the models be checked rather than renamed: what each one is, where it lives, and how the app connects to it. The user later clarified that hiding the chat while the deck is open is acceptable because the deck is collapsible, and chose live model fetching over a curated static list.

This spec covers the tier abstraction, the live catalog, and the deck layout. It deliberately supersedes the deck-visibility decision in `2026-11-27-full-mode-deck-and-settings-discoverability-design.md`.

## Evidence gathered

- `src/Slop.Config.ps1:21` sets `$script:SlopBrains = @('builtin','custom','opencode')`; these are brains, not tiers, and `custom` is exposed as a third choice.
- `src/Slop.Config.ps1:114` gives OpenCode only two models, `big-pickle` and `beam-free`. That is why most free models vanished from the UI.
- `src/Slop.Config.ps1:77` points the bundled brain at `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` in the app root; `src/Slop.Config.ps1:96` defaults the model to `big-pickle`.
- `src/Slop.Config.ps1` already has `Set-SlopConfigBrain`, which validates brain/model/endpoint combinations; no new write path is needed.
- `src/Slop.ControlDeck.ps1:26-41` caps the deck body at 220px and reserves 140px for transcript and 90px for composer. `src/Slop.ChatWindow.ps1:176` pins `Height="220"` and line 183 adds `VerticalScrollBarVisibility="Auto"`. That is the scrollbar the user sees.
- `src/Slop.ChatWindow.ps1:100-106` defines four rows: chrome (`34`), deck (`Auto`), transcript (`*`), composer (`Auto`). `ChatDeckPanel` is in row 1 only.
- `src/Slop.OpenCode.ps1:145-168` provides `New-SlopOpenCodeAuthHeader`; `src/Slop.Route.ps1:129` already calls it with `-ServiceConfigPath $Config.serviceConfigPath -BaseUrl $baseUrl`. Live catalog fetch reuses this exact pattern.
- Live probe against the running service on `http://127.0.0.1:28894` with Basic auth:
  - `/api/info` reports OpenCode 2.4.2.
  - `/api/model` returns a JSON object with a `data` array. A sample entry carries `id`, `modelID`, `providerID`, `type`, `name`, `settings.baseURL`, `capabilities`, `cost[]`, `status` and `enabled`.
  - The array has 64 entries, all `type=chat`. 15 entries have zero input and output cost; two ids are duplicated (`hy4-flash-free`, `beam-free`), leaving 13 unique free chat models.
  - `big-pickle` is present, zero-cost, and described as a reasoning model for deliberate analysis, multi-step problem solving and tool use.
  - Free ids observed include `seaglass-alpha-free`, `hungerg-free`, `tidepool-alpha-free`, `hy4-flash-free`, `iceman-free`, `iceman-contributor-free`, `flint-40b-free`, `deepseek-v4.1-flash-free`, `nemotron-3.5-super-vl-free`, `beam-free`, `mimo-v2.6-flash-free`, `nemotron-3.5-lightning-free` and `big-pickle`.
  - Catalog entries point at `https://opencode.ai/inference/openai/v1` and `https://opencode.ai/inference/go/openai/v1`. Sloppy does **not** connect to those URLs directly; the local OpenCode service is the only hop.
  - Raw catalog responses include an `x-opencode-org-id` header. Raw JSON and headers must never be written to logs, status text or UI.
- `docs/architecture.md` documents Tier 1 locally through llama.cpp with the LFS-tracked GGUF and `--jinja`. Tier 2 goes through the loopback OpenCode service and agent `sloppy`; `openCodeBaseUrl` defaults to `http://127.0.0.1:28894`.

## Goals

- Present exactly two selectable tiers in the UI: Tier 1 (local LLM) and Tier 2 (OpenCode).
- Give Tier 2 a live, filtered list of free chat models with `big-pickle` as the default.
- Make the expanded deck show a whole section with no inner scrollbar.
- Keep every change headless-testable and RED-first.
- Keep credentials, org identifiers and raw catalog payloads out of the UI and logs.

## Non-goals

- No directory relocation, model-root picker or voice-root picker.
- No change to voice input, Whisper readiness or TTS.
- No custom-tier UI entry point; `custom` stays valid only in config and runtime.
- No change to the main-window Settings read-only Advanced fields beyond their displayed route/tier text.
- No push, tag, release, deploy, force-push or visibility change.
- No live visual or voice claim by the agent; the user confirms appearance and behavior.

## Decisions

- A tier is a UI-facing label over an existing brain. Tier 1 maps to `brain=builtin`. Tier 2 maps to `brain=opencode`.
- The picker has exactly two entries. `custom` is not offered. A config that loads with `brain=custom` still works; the tier combo shows no selection and the status text says the active custom route must be edited in config.
- Tier 1 always uses the bundled GGUF and never fetches a catalog.
- Tier 2 models come from the local OpenCode service at `/api/model`, authenticated with the existing header helper. The list is fetched live, cached per session, and refreshable.
- Catalog filtering keeps only active, enabled, zero-cost chat models, deduplicates by `id` (preferring `providerID='opencode'`), pins `big-pickle` first and sorts the rest by name.
- A failed or offline fetch shows an explicit error in deck status and leaves the saved model untouched. An empty or stale catalog never clears a valid saved value.
- When expanded, the deck covers the transcript and composer rows; the user approved hiding chat while settings are open. Collapsing restores chat exactly.
- The deck body takes all remaining height and has no `ScrollViewer`. The chat window grows to a preferred full height clamped to the work area, then restores the exact previous size on collapse.
- The prior spec's rule that transcript and composer stay visible while the deck is open is reversed by this decision.

## Architecture

### Tier model

`src/Slop.Config.ps1` gains pure tier contracts alongside the brain contracts:

- `Get-SlopTierCatalog` returns an ordered list of `@{ Id='tier-1'; Label='Tier 1 - Local LLM'; Brain='builtin'; DefaultModel='Qwen3.5-2B Q4_K_M' }` and `@{ Id='tier-2'; Label='Tier 2 - OpenCode'; Brain='opencode'; DefaultModel='big-pickle' }`.
- `Resolve-SlopTierFromConfig -Config` returns `tier-1`, `tier-2`, or an empty string for `custom`/unknown values.
- `Get-SlopTierDefaultModel -TierId` returns the bundled local model name for Tier 1 and `big-pickle` for Tier 2.
- `Resolve-SlopTier` stays as a compatibility wrapper returning `1` for Tier 1, `2` for Tier 2 and `0` for custom/unknown, so existing callers and tests keep working.
- `Set-SlopTierConfig` is a thin wrapper over `Set-SlopConfigBrain`: Tier 1 forces `builtin` and leaves the bundled `localModelFile` in place, restoring the config default if absent; Tier 2 forces `opencode`, the loopback base URL, agent `sloppy` and the selected model. It applies no new validation rules.

### Model catalog module

New `src/Slop.ModelCatalog.ps1`, headless and free of WPF:

- `Get-SlopFreeChatModels -CatalogData` is the pure filter. It accepts either the decoded response object or the `data` array, checks `type='chat'`, `enabled -ne $false`, `status='active'`, and treats all `cost[]` entries with zero `input` and `output` as free. It deduplicates by `id`, prefers `providerID='opencode'` when an id repeats, pins `big-pickle` first, sorts the rest ordinally by `name`, and returns only `@{ Id; Name }`.
- `Get-SlopModelCatalogResult -BaseUrl -Headers` performs `GET {BaseUrl}/api/model`, decodes JSON, and returns `@{ Ok; Models; Error }`. It never returns raw payload or headers. `BaseUrl` must pass the existing loopback URL validator.
- `Get-SlopModelCatalogStatusText -Result` produces short UI copy for success, failure and empty results.

The WPF shell resolves the base URL from config/env exactly as `Get-SlopEffectiveOpenCodeBaseUrl` already does, builds headers with `New-SlopOpenCodeAuthHeader -ServiceConfigPath $Config.serviceConfigPath -BaseUrl $baseUrl`, and calls the two functions. Fetch happens when the deck Model section is first opened with Tier 2 selected, and on explicit Refresh. Results are cached in session state and invalidated on Refresh.

### Deck layout

`src/Slop.ChatWindow.ps1` changes:

- `ChatDeckPanel` spans `Grid.Row="1"` through `Grid.RowSpan="3"` so it occupies the transcript and composer area while open.
- `DeckBody` drops `Height="220"` and becomes stretch-filled.
- The inner `ScrollViewer` around the deck sections is removed; sections sit directly in the body grid.
- Deck Model card replaces the free-text `DeckModelBox` with `DeckTierCombo` (two options), `DeckModelCombo` (live free chat models), `DeckModelRefreshButton` and `DeckStatusText`. `DeckModelRouteText` and `DeckModelSaveButton` remain.
- Settings card margins are tightened enough for the new dropdowns to fit at full height.

`src/Slop.ControlDeck.ps1` changes:

- `Get-SlopDeckBodyHeight -WindowHeight -DeckOpen -FixedHeight=88 -OuterMargin=16` returns `0` when closed and `WindowHeight - FixedHeight - OuterMargin` when open, with no 220px cap and no transcript/composer minima. `OuterMargin` accounts for the deck panel's outer border and padding.
- New `Get-SlopDeckExpandedWindowHeight -WorkAreaHeight -CurrentHeight -PreferredHeight=620` returns `min(WorkAreaHeight, max(PreferredHeight, CurrentHeight))`, so the deck never shrinks the window and never exceeds the work area.
- The shell records the exact window height and pane mode before expanding, applies the expanded height, and restores both on collapse.

## Components

### Tier picker

- Two selectable entries only. Selecting Tier 1 disables the model combo and shows the bundled model name as read-only text.
- Selecting Tier 2 enables the model combo and triggers the catalog fetch if nothing is cached.
- Saving a tier writes through `Set-SlopTierConfig`; the effective route text updates from config afterward.

### Model dropdown

- Populated from `Get-SlopFreeChatModels`, with `big-pickle` first.
- The saved model is preselected even if the current catalog no longer lists it; in that case a short note says it is not in the current catalog, but it stays selectable and unchanged.
- Refresh re-fetches without touching saved config.

### Deck overlay

- Expanding hides `ChatScroll` and `ChatInputChrome` and shows the deck body; the six section buttons remain available in the strip.
- Collapsing restores `ChatScroll`, `ChatInputChrome`, the previous window height and the previous pane mode.
- The header deck toggle and the strip chevron drive the same `ChatDeckOpen` state.
- Section switching changes only the visible section, never chat visibility or window size.

## Data flow

1. User opens the deck Model section and selects Tier 2.
2. Shell computes the loopback base URL and builds auth headers from config/env.
3. Shell calls `Get-SlopModelCatalogResult`; service returns `/api/model` JSON.
4. `Get-SlopFreeChatModels` maps it to `{Id, Name}` only; raw payload and headers are discarded.
5. Shell fills `DeckModelCombo`, preserving the saved value.
6. Save calls `Set-SlopTierConfig`, which delegates to `Set-SlopConfigBrain`, then refreshes route text and overview state.
7. Deck expand/collapse adjusts body height and window size through the two pure layout helpers.

## Error handling

- Service unreachable, non-200 response, malformed JSON, missing password or non-loopback URL: `Ok=$false`, a short error in `DeckStatusText`, saved model unchanged.
- Empty filtered list: explicit "no free chat models returned" status; saved model unchanged.
- Duplicate ids: first occurrence wins, preferring `providerID='opencode'`.
- Config unavailable: tier picker shows no selection and Save reports that config is unavailable.
- Small work area: expanded window height is clamped to the work area. With no body scrollbar, a section taller than the clamped space can clip; the user can resize the window manually. This residual case is documented under Risks.
- Config write failure: status shows the exception message; in-memory config remains valid.

## Verification

- RED-first pure tests for `Get-SlopTierCatalog`, `Resolve-SlopTierFromConfig`, `Get-SlopTierDefaultModel` and the `Resolve-SlopTier` compatibility wrapper.
- RED-first catalog filter tests with fixtures for duplicates, paid models, non-chat types, disabled/inactive entries, offline failure and empty results; assert only `{Id, Name}` escapes the module and `big-pickle` is first.
- RED-first layout tests for `Get-SlopDeckBodyHeight` closed/open/large-window cases and `Get-SlopDeckExpandedWindowHeight` normal/clamped cases.
- Static XAML/wiring tests: no `ScrollViewer` inside `DeckBody`, `Grid.RowSpan="3"` on `ChatDeckPanel`, exactly two tier entries, no `custom` entry, no hardcoded user paths.
- Behavior tests: section switching does not alter chat visibility; collapse restores height and mode; Tier 1 triggers no catalog call.
- Existing config, shell, shutdown, transparency, brand and chat suites stay green.
- Recompute CodeTour anchors after source line shifts.
- Final gates: focused suites, tour check, canonical verify, review, `git diff --check`, clean status and divergence check.

## Acceptance criteria

- The model picker shows exactly Tier 1 and Tier 2; Custom is not offered.
- Tier 1 uses the bundled local GGUF and makes no network call.
- Tier 2 defaults to `big-pickle` and offers the live free chat models from the local OpenCode catalog.
- Selecting a tier and saving changes the underlying brain and model correctly, and route text reflects it.
- The expanded deck shows a whole section with no scrollbar and hides chat; collapsing restores chat and the previous window size.
- No raw catalog payload, header, org id, credential or hardcoded user path appears in UI, logs, tests or docs.
- A failed catalog fetch never clears or replaces a valid saved model.
- No push, tag, release, deployment or visibility change occurs.

## Risks and trade-offs

- Live fetch depends on the local OpenCode service and its credential; the explicit failure state is the mitigation.
- Local catalog entries change over time; the filter and dedupe are defensive but the list is not frozen.
- Hiding chat while the deck is open is a deliberate user-approved reversal of the previous layout.
- Deck expansion overrides window height temporarily; restoring the exact prior size and mode is covered by tests.
- The 620px preferred height is a heuristic clamped to the work area; very small displays may still require manual resize.

## Follow-ups

- Directory relocation and folder pickers stay deferred to their own spec.
- If the user later wants Custom in the UI, add it as an explicit advanced tier with its own spec rather than reintroducing it silently.
