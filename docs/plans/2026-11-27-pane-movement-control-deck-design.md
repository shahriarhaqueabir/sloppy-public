# Design: movable panes, control deck, capabilities and clean shutdown

Date: 2026-11-27
Status: Approved in brainstorming; implementation not started.

Note on location: `docs/superpowers/` is gitignored in this public repo, so the
canonical tracked copy of this spec lives in `docs/plans/`, matching the existing
design-doc convention. The interactive mockup used for approval was a local-only
artifact and is not tracked.

## Context

The current three-view baseline (pea, expanded chat, large chat) is accepted and
must not regress. The user reported four gaps and then added two more:

1. Expanded and maximised panes cannot be moved.
2. The maximised view needs a **command / control / overview** sidebar: settings,
   manageable data, and "what's happening under the hood".
3. There is no WPF way to shut Sloppy down. A direct voice phrase is preferred.
4. In expanded view the pea-sized Sloppy should stay visible at the exact click
   point that opened the chat.
5. Conversation text should be copyable — clarified during brainstorming to
   **selectable text only**, no buttons and no speech synthesis.
6. Sloppy is an SLM-backed talker (~2B/4B) with no tool switches. End users need
   toggles for tools and skills so they can customise its capabilities.

The repo already has a deny-first capability system in
`src/Slop.OpenCodeProfile.ps1`: `companion` / `workspace` / `power` profiles,
secret and cloud-metadata denies, shell denials, and fail-closed verification via
`Test-SlopEffectivePermissions`. The new toggles extend this system; they do not
introduce a second permission model.

## Goals

- Keep the pea visible and unmoved at its original click coordinates while the
  chat is in Expanded mode.
- Hide the pet entirely in Maximized mode and restore it, at the same coordinates,
  when returning to Expanded or closing chat.
- Make both Expanded and Maximized panes draggable with work-area clamping.
- Add a control deck sidebar with Overview, Settings, Data, Tools & Skills,
  Under the hood, and Exit sections.
- Make conversation bubbles selectable text.
- Expose six opt-in capability toggles on top of the deny-first profile base.
- Add a WPF shutdown action and a `Sloppy, shutdown` phrase path with confirmation.
- Prove every rule with RED/GREEN headless tests before claiming it works.

## Non-goals

- No Copy buttons, clipboard feature, or text-to-speech read-aloud.
- No true OS/work-area-filling fullscreen. "Maximized" is a large draggable preset.
- No raw permission-JSON editor, no new permission backend, no new audio backend.
- No Mica, Acrylic, DWM backdrop, or system-material substitute. The pet and chat
  window keep `WindowStyle="None"`, `AllowsTransparency="True"`,
  `Background="Transparent"`; readability comes from dark internal backplates.
- No new top-level window for the sidebar; it lives inside the transparent chat pane.
- No change to the accepted pea-only view, the local brain route, or the voice
  transcription engine.
- No touch to `data/`; no push, tag, release, deploy, force-push, or visibility change.
- No live visual claim by the agent; the user verifies appearance and voice behavior.

## Decisions

### Pane modes and movement

- Keep the existing mode identifiers `Extended` and `Full` so tests, tour anchors,
  and persisted state stay compatible. `Full` is now a **large preset** inset from
  the work area by a small margin, not a work-area-filling surface.
- Both modes get a header drag grip. Dragging uses the WPF drag primitive and the
  existing `Get-SlopWorkAreaClampedRect` guard on `LocationChanged`.
- `Get-SlopChatWindowRect` gains a pin-aware placement rule used at open time and
  on mode switches: when the pet is pinned, the chat rect is offset to a side that
  does not overlap the pet's exact rect. A deliberate user drag may overlap it;
  pinning is an opening invariant, not a permanent collision constraint.
- Entering `Full` collapses the pet window (hidden, non-interactive) and stores its
  rect. Returning to `Extended` or closing chat restores visibility and the stored
  rect. The pet is never moved or resized by any of these transitions.

### Control deck

- A collapsible left sidebar inside the chat window, using the existing dark fills
  (`#F21E293B` / `#263348`) and the 2px `#8893A4BD` border. Window transparency is
  unchanged.
- Sections: **Overview** (route, brain/model, session, signal count, copy-free read
  of conversation length), **Settings** (existing settings surfaced without a
  second settings implementation), **Data** (local-data and session actions routed
  through `src/Slop.Surfaces.ps1` scope contracts with explicit confirmation),
  **Tools & Skills** (the six toggles), **Under the hood** (read-only effective
  route, endpoint, agent id, motion/stream state), **Exit** (shutdown).
- The deck opens by default in `Full`; a header button can reveal it in `Extended`.

### Selectable conversation text

- Chat bubbles become selectable read-only text. The exact WPF control is verified
  during planning (read-only `TextBox` versus `TextBlock` selection support); the
  implementation must not steal focus, add borders, or change bubble geometry.
- No Copy/Export button is added; the user drags over text to select it.

### Capability toggles

- Six toggles, all default off: workspace files, web access, shell commands,
  skills/plugins, subagents/tasks, external folders.
- `companion` remains the base profile. Enabling a toggle adds a narrowly-scoped
  allow rule through `New-SlopControlledConfig`; it never broadens a wildcard rule.
- Immutable hard denies stay in force: secrets (`service.json`, `.env*`, `.ssh`,
  `.aws`, gcloud), cloud metadata, loopback/`file://` `webfetch`, and the shell
  denials (including `sudo` / `rm -rf` where the profile defines them). No UI path
  can remove them.
- Config v3 gains a `capabilityToggles` hashtable with validation that rejects
  unknown keys and fails closed. Existing v3 configs without the field receive the
  all-off default. Applying toggles reruns `Test-SlopEffectivePermissions`; a
  failed verification keeps the previous effective config and shows the reason in
  the deck.
- Web access and shell carry explicit disclosure copy because they can reach
  beyond this PC or change files.

### Shutdown

- A pure phrase parser shared by voice and typed input. Voice is transcribed to
  text before it reaches Sloppy, so both paths are the same text path.
- `Sloppy, shutdown` (normalized: case/punctuation tolerant, comma optional)
  sets a pending state and replies "Are you sure? Say or type yes."
- The next input is evaluated by an intent resolver: `yes` / `y` / `confirm`
  runs shutdown; anything else cancels the pending state and is handled normally.
- All shutdown entry points — voice/typed phrase, sidebar Exit button, tray item —
  use the same confirmation step for consistency.
- Clean teardown reuses the existing `$window.Add_Closed` work: stop timers, cancel
  the current stream, reject pending approvals, delete the OpenCode session, close
  chat, then `Application.Current.Shutdown()`. No orphan process.

## Architecture / files

Pure, headless logic first; WPF stays a thin view.

- `src/Slop.ChatWindow.ps1` — pin-aware rect resolution, large-preset sizing,
  mode/pet-visibility contract.
- `src/Slop.OpenCodeProfile.ps1` (or a small companion pure module) — toggle
  catalogue, toggle-to-rule conversion, immutable-deny guard, config validation.
- `src/Slop.Config.ps1` — `capabilityToggles` defaults, validation, v3 migration.
- New `src/Slop.Shutdown.ps1` — phrase normalization, intent resolver, clean
  teardown command composition (headless).
- `src/Slop.ps1` — chat header drag wiring, pet hide/restore, deck event wiring,
  selectable bubbles, shutdown interception before `Start-Stream`.
- Chat XAML in `src/Slop.ChatWindow.ps1` — deck layout, drag grip, read-only text.
- Tests under `tests/` — focused RED reproducers per behavior; tour anchors
  refreshed after source line shifts.

## Verification

- RED reproducer committed as `test:` before each GREEN change, using explicit
  file paths only. No `git add -A`, no `git add .`.
- Focused suites: chat/transparency geometry, shell wiring, IA, config, profile,
  shutdown, tour anchors.
- Canonical verify gate with explicit `FailedCount` read; a zero exit code alone
  is not proof.
- `git diff --check`, review gate, and clean working tree at each boundary.
- Restart with `tools/slop-control.ps1` and ask the user to visually confirm the
  three scenes and voice confirmation. The agent makes no live visual claim.

## Risks and trade-offs

- Dragging a transparent, topmost WPF window can fight clamping; clamp on
  `LocationChanged` with a tolerance so it does not oscillate.
- Hiding the pet in `Full` must preserve its rect exactly; storing and restoring
  the rect is safer than recomputing from the chat pane.
- Capability toggles touch a security boundary. Fail closed, keep hard denies
  immutable, and re-verify effective permissions before enabling a route.
- PowerShell event handlers do not close over function locals; publish values to
  script scope or re-fetch controls inside handlers.
- Source edits will stale CodeTour anchors and inline line references; refresh and
  re-run the tour check in the same stream.

## Open questions resolved in brainstorming

- Copy/read-aloud? No — selectable text only.
- True fullscreen? No — large draggable preset.
- Pea in maximized? Hidden; visible and pinned in expanded.
- Toggle scope? Core six, all off by default.
- Shutdown confirmation? Yes — `yes` via voice or typed text.
