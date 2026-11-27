# Implementation Plan — Sloppy Product Experience

**Date:** 2026-11-27
**Spec:** `docs/plans/2026-11-27-product-experience-design.md` (tracked)
**Predecessor:** `docs/plans/2026-11-27-companion-window-and-live-fixes-plan.md` (approved; its carried-forward items are folded into T3/T4 below)
**Execution:** inline, no subagents, bounded RED→GREEN pairs, one explicit-path commit per task.
**Gates:** no push/tag/release/deploy/visibility change; `data/` untouched; live UI checks belong to the user.

## Ordering rationale

Tokens and particle math are pure and dependency-free, so they land first and stay easy to attribute. The transparent chat window then establishes the shell that all later UI work targets. Live fixes and information architecture come after that shell exists, so no work is done twice. Repo hygiene is independent and lands late to avoid churning docs whose line numbers move during implementation. Final anchor refresh comes last because every XAML/source edit can stale the tour.

## Task table

| Task | RED contract | GREEN change | Explicit commit paths | Focused gate |
|---|---|---|---|---|
| T1 Design tokens | New `tests/slop-design-check.ps1` fails: module absent, palette/copy/contrast functions missing. | Add `src/Slop.Design.ps1` with pure `Get-SlopDesignToken`, `Get-SlopCopy`, `Test-SlopContrast`; no WPF types. | `src/Slop.Design.ps1`, `tests/slop-design-check.ps1` | `pwsh -File tests/slop-design-check.ps1` |
| T2 Particle field | Extend `tests/slop-face-check.ps1`: 32 dots, radius 0.46, size max 2.6, frozen determinism, 96x96/inset 4. | Update `Initialize-SlopFaceDots`, `New-SlopFaceLayer`, `Update-SlopFaceLayer` with pinned count, wider radius, radial alpha falloff, token palette. | `src/Slop.Face.ps1`, `tests/slop-face-check.ps1` | `pwsh -File tests/slop-face-check.ps1` |
| T3 Transparent chat window | New `tests/slop-transparency-check.ps1` fails: chat module absent, XAML contract unverifiable, forbidden material APIs present, no clamp function. | Add `src/Slop.ChatWindow.ps1`: one transparent window for expanded and full-work-area modes, work-area clamp, ScrollViewer routing, title-bar mode toggle; wire `src/Slop.ps1` to open it. | `src/Slop.ChatWindow.ps1`, `src/Slop.ps1`, `tests/slop-transparency-check.ps1` | transparency + shell checks |
| T4 Live fixes | Static assertions fail for `[empty response]` fallback, wizard preview handler scope, scroll routing, membrane padding, outline layering, pet position preservation. | Apply carried-forward fixes in `src/Slop.ps1` and `src/Slop.Onboarding.ps1`. | `src/Slop.ps1`, `src/Slop.Onboarding.ps1`, tests | affected check suites |
| T5 Surface IA | Static assertions fail for concept ownership, plain primary labels, Advanced expanders, on-page status. | Regroup Settings/Customization/Brain/Privacy; simplify onboarding screen 4; consume token copy. | `src/Slop.ps1`, `src/Slop.Onboarding.ps1`, tests | shell + onboarding checks |
| T6 Repo hygiene | Static assertions fail for machine paths, Whisper contradiction, `data/` ignore, duplicate dot-sources, stale doc claim. | Replace four personal paths; align architecture/plan Whisper wording; add `/data/` to `.gitignore`; remove Provider duplicates; correct `.muted` doc claim. | doc paths, `.gitignore`, `src/Slop.Provider.ps1`, tests | hygiene check suite |
| T7 Anchors and gates | Tour anchor probe reports drift after source line shifts. | Recompute `.tours/architect-slop-architecture.tour` anchors and inline line refs only where drift is real. | tour file only | tour check + full gates |

## Task detail

### T1 — Design tokens

`src/Slop.Design.ps1` must be importable without WPF assemblies. Exports:

- `Get-SlopDesignToken -Name <string>` — returns surface, text, mark, type, spacing, motion, and status values from one ordered hashtable.
- `Get-SlopCopy -Key <string>` — returns canonical strings, including "Sloppy" in prose and "S.L.O.P." as the mark, plus the five status labels.
- `Test-SlopContrast -Foreground <hex> -Background <hex>` — returns the WCAG ratio `(L1+0.05)/(L2+0.05)`; primary text on glass must be >= 4.5.

Pinned token values: surface app `#12141C`, panel `#1E293B`, raised `#263348`, glass `#18FFFFFF`; text primary `#EAEAEA`, secondary `#B8B8C0`, subtle `#93A4BD`, accent `#A5B4FC`; mark colors unchanged; fill primary `#4F46E5`, hover `#4338CA`, secondary `#14B8A6`, destructive `#7F1D1D`; status text `#FDE68A`/`#86EFAC`/`#FCA5A5`; type floor 11px and title 14/18/24; durations 100/200/300/500/1000ms.

Tests assert: module contains no `System.Windows` type, every token name resolves, no duplicate colour literal across the module, `#8A8A96` and `#6366F1`-with-white are absent from informational text/fill roles, all informational text tokens exceed 4.5:1 on base, panel, and glass, copy keys used by surfaces exist, and every status has a label token.

### T2 — Particle field

Pinned numbers from the spec. Tests must verify:

- `(Get-SlopFaceDots).Count -eq 32`.
- Scatter constant for ring/spiral/orbit is `0.46`; former `0.40` occurrences are gone in those branches.
- Generated dot `Size` never exceeds `2.6`.
- Calling `Update-SlopFaceLayer -Frozen $true` twice at different times yields identical normalized positions and unchanged transition state.
- Every normalized position stays in `[0,1]` after clamp.

Alpha falloff is computed from distance to centre; it changes opacity only, not position, so existing position tests remain valid.

### T3 — Transparent chat window

`src/Slop.ChatWindow.ps1` owns a single WPF window used for both modes. Hard assertions:

- XAML contains `WindowStyle="None"`, `AllowsTransparency="True"`, `Background="Transparent"`.
- No `MicaController`, `AcrylicBrush`, `BackdropType`, `DwmSetWindowAttribute`, `SetWindowCompositionAttribute`.
- Work-area clamp function bounds the window inside the primary monitor's working area in both modes.
- ScrollViewer handles mouse wheel; overlays set `IsHitTestVisible=false` where they must not intercept.
- Full-work-area toggle lives in this window, not on the pet.
- If window construction throws, the pet remains interactive (chat helper returns cleanly).

### T4 — Carried-forward live fixes

Each fix has one static assertion before and after:

- `reasoning_content` only replies use the thinking fallback instead of `[empty response]`.
- Wizard preview handler is bound in the correct scope (regression of `fd4931a`).
- Mouse wheel scrolls chat through ScrollViewer.
- Membrane padding and frame outline layering match the approved design.
- Pet position is preserved when opening chat.

### T5 — Surface information architecture

- Settings: Companion/Brain/Voice/Startup groups; raw provider/model/agent fields moved into an `Advanced` expander; effective route shown read-only.
- Customization: sole ongoing owner of name/colour/personality/persona text.
- Brain: plain tier choice first; raw fields in `Advanced`; readiness/status on page.
- Privacy: same three deletion actions, clearer copy, in-page status.
- Onboarding: plain-language route choice; raw fields behind `Advanced setup`; one opt-in for voice; initial identity values only.
- Every primary label is plain language; helper lines explain non-obvious inputs.
- No success message is written to a hidden chat surface.

### T6 — Repo hygiene

- Replace `C:\Users\shahr\...` in the two tracked plan docs with `$HOME` or repo-relative equivalents.
- Align `docs/architecture.md` and the Qwen plan with the tracked Whisper artifacts; keep `README.md:114` as the truth.
- Add `/data/` to `.gitignore`; do not stage, edit, or delete any `data/` file.
- Remove duplicate `Slop.LocalModel.ps1` / `Slop.Route.ps1` dot-sources from `src/Slop.Provider.ps1`.
- Correct the `.opencode/opencode.jsonc.muted` documentation claim to match the guarded test.

### T7 — Final gates

Refresh tour anchors only after all source edits settle. Run the full verify, test, review, and diff gates from their dedicated plans. Report evidence; hand live UI checks to the user.

## Commit discipline

- `git add` with explicit paths only. Never `git add -A` or `git add .`.
- Confirm `git status --short` shows `?? data/` and nothing else staged from that directory.
- Each commit message: `test: ...` for RED, `feat:`/`fix:`/`docs:` for GREEN, `docs: refresh tour anchors` for T7.
- If a task fails its focused gate, fix in place before committing; do not carry a red gate forward.
