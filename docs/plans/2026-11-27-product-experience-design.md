# Sloppy Product Experience — Unified Design and Feature Review

**Date:** 2026-11-27
**Status:** Design fixed by the agent under an explicit autonomous mandate; the user waived interim check-ins and approvals for this session.
**Scope:** Public Sloppy repo — pea, expanded chat, full-work-area chat, Settings, Customization, Brain, Privacy, onboarding, voice, Tier 1/Tier 2 routes, and the shared visual language.
**Relationship to existing work:** Carries forward `docs/plans/2026-11-27-companion-window-and-live-fixes-design.md` (transparent separate chat window, work-area clamping, thinking fallback, wizard scope fix, scrolling/padding/outline). This spec adds the full-product review and the unified design layer.

## Context

The user asked for more than a prettier pea: "not just work on the pea sized sloppy, but also the expanded and full screen views, for: settings, customization, onboarding, better logical human friendly approach to these options... every feature and functionality needs a review and improvement."

Current-state review found four structural problems:

1. **One concept, many homes.** Brain/route fields appear in onboarding screen 4, the Settings panel, and the Brain panel. Voice enable/language appear in onboarding and Settings. Colour and personality appear in onboarding and Customize. Each surface uses different labels and control types, so the user cannot form one mental model.
2. **Advanced internals lead the flow.** Provider, model, agent id, and loopback endpoint are presented as primary choices during first run, before the user knows what they mean.
3. **No shared design contract.** Colours, sizes, type sizes, status tones, and copy are repeated as literals across `Slop.ps1`, `Slop.Motion.ps1`, `Slop.Face.ps1`, and `Slop.Onboarding.ps1`. There is no single place to change a token or a voice rule.
4. **The live visual layer is thin.** The compact particle field is 12 dots in a 72x72 rounded clip with small drift; the requested wider scatter and richer motion have no owning module or test contract.

A repository audit added concrete hygiene defects (machine paths in tracked docs, a contradictory bundled-Whisper claim, app data that is neither tracked nor ignored, and duplicate module dot-sourcing). Those are in scope as small, conservative fixes.

## Goals

1. Review every user-facing feature and record an explicit keep/change/defer decision.
2. Give each concept exactly one ongoing control surface; other surfaces show the resulting fact read-only.
3. Replace raw developer fields with plain-language choices first and advanced disclosure second.
4. Introduce a pure, testable design-token and copy layer used by all surfaces.
5. Enrich the pea with a wider, more dynamic particle field that respects reduced motion and signal states.
6. Make expanded and full-work-area chat share one transparent, work-area-clamped shell with one visual language.
7. Fix the audited name/link/directory/path drift conservatively.
8. Keep every change provable by focused RED→GREEN tests and static guards.

## Non-goals

- No Mica, Acrylic, DWM backdrop, or any material that replaces the transparent WPF surface. Transparency is a hard contract in compact, expanded, and full-work-area modes.
- No third tier, new provider, new brain, credential handling, or change to the Tier 1/Tier 2 selection logic.
- No config schema migration; `config.json` v2 stays as-is.
- No push, tag, release, deploy, force-push, or visibility change.
- No agent claim of live visual verification; the user performs live UI checks.
- No modification, deletion, or commit of any file under `data/`. An ignore rule may be added to protect those files, but their contents stay untouched.
- No invented features beyond clarity, consistency, and the requested visual richness.

## Decisions

### Chosen approach: single source of truth + progressive disclosure + token layer

| Approach | Trade-off | Verdict |
|---|---|---|
| Polish each page in place | Smallest diff, but preserves duplicated concepts and copy drift. | Rejected |
| Rewrite all UI in a new XAML module | Clean architecture, but large churn in tour anchors, handlers, and tests. | Rejected |
| One source of truth per concept, progressive disclosure, shared pure token layer | Moderate diff; removes duplication and gives one place for visual/voice rules; keeps existing config and page pattern. | **Chosen** |

### Hard visual contract

- `WindowStyle="None"`, `AllowsTransparency="True"`, `Background="Transparent"` on the pet and both chat modes.
- No `MicaController`, `AcrylicBrush`, `BackdropType`, `DwmSetWindowAttribute`, or `SetWindowCompositionAttribute` anywhere in tracked source.
- A static test asserts the XAML contract and scans source for forbidden API names.

### Concept ownership

Onboarding is a one-time setup surface: it may write initial values for identity and route, then hands ongoing ownership to the surfaces below. After first run, each concept has exactly one writable home.

| Concept | Owner surface | Other surfaces |
|---|---|---|
| Companion name, colour, personality, persona text | Customization | Onboarding sets initial values only; pea/chat reflect them. |
| Brain tier, provider, endpoint, model, agent id, capability profile | Brain | Onboarding makes the initial plain-language route choice; Settings shows effective route read-only; Privacy shows disclosure. |
| Voice enable, language, max seconds | Settings | Onboarding offers a single opt-in and language; wizard preview reflects it. |
| Data route / disclosure / deletion | Privacy | Route badge and onboarding link here. |
| Autostart, data location, About | Settings | Read-only display. |
| Chat mode (expanded / full work area) | Chat window title bar | Pet open button opens the same window. |

### Progressive disclosure

- Onboarding asks what a person can answer: name, look, personality, then "where answers come from" as plain choices. Raw provider/model/agent fields move behind an "Advanced setup" expander.
- Settings and Brain lead with readable values and dropdowns; raw strings stay under an "Advanced" expander with one-line explanations.
- Every input gets a plain label and, where non-obvious, one short "what this does" line. No jargon in primary labels.

### Design tokens and voice

- A new pure module `src/Slop.Design.ps1` owns: surface colours, text roles, type scale, spacing scale, motion durations/easings, status tones, and canonical UI copy strings. It follows the Design Tokens Community Group model conceptually (primitive → semantic → component) but stores values in a PowerShell hashtable because this app has no token pipeline.
- Brand voice: "Sloppy" in prose, "S.L.O.P." as the product mark. Calm, local-first, honest about the route. Short sentences. No hype, no euphemism for remote data. The pea signals; it does not speak.
- Existing colours are retained as mark colours (#6366F1 ocean, #14B8A6 moss, #A855F7 plum, #EC4899 ember, #38BDF8 sky, #94A3B8 stone) so this is unification, not rebranding. Informational text uses light variants, never the raw marks.
- Contrast is a tested token rule, not a preference. Measured against `#12141C` base, `#1E293B` panel, and the `#18FFFFFF`-over-base glass composite (~`#282A31`):
  - `#EAEAEA` primary, `#B8B8C0` secondary, `#93A4BD` subtle, `#A5B4FC` accent — all >= 5.6:1 on all three surfaces.
  - `#8A8A96` is retired from informational text: 4.20:1 on glass, below AA 4.5:1. Replace with `#93A4BD`.
  - Filled primary actions use `#4F46E5` with white text (6.29:1); current `#6366F1` is 4.47:1 and fails AA.
  - Status text uses light variants: `#FDE68A` thinking, `#86EFAC` working/success, `#FCA5A5` error. Raw `#EF4444` on panel is 3.89:1 and must not be used as text.
- State is never colour-only (WCAG 1.4.1): every status has a redundant shape/glyph and a text label ("Idle", "Thinking", "Working", "Done", "Needs you").
- Type floor is 11px for informational text; 9px labels are raised or merged. Motion tokens follow Material 3: 100ms control, 200ms toggle, 300ms panel, 500ms pet, 1000ms ambient. Ambient motion is pausable and disabled under reduced motion.
- Transparency caveat: translucent text areas need a dark composited backplate or scrim so contrast does not depend on the user's wallpaper. The transparent window contract stays; the backplate is inside it.

### Particle field — pinned contract

- Dot count is pinned at **32** (audited current: 12). No randomness in count.
- Normalized scatter radius rises from ~0.40 to **0.46** for ring/spiral/orbit families; size range becomes **1.0–2.6** with a radial alpha falloff so the aura reads soft, not clipped.
- Compact aura region grows from **72x72 to 96x96** with inset **4**; the expanded body keeps its path clip.
- Frozen and reduced-motion states produce identical positions and no phase drift. Signal state continues to drive pattern and speed.

## Feature review matrix

| # | Feature | Current state | Decision |
|---|---|---|---|
| 1 | Pea motion (idle actions, hops, breathing, lean, shadow) | Rich spring state machine; 9 idle actions. | Keep; consume design tokens for status tone only. |
| 2 | Face patterns (24 patterns) | 12 dots, hard clamp, pattern transitions. | Improve: 32 dots, wider scatter, soft falloff, token palette. |
| 3 | Signal colour/shape | Event priority resolver with sticky/transient events. | Keep semantics; rename literals to tokens; no opacity ghost. |
| 4 | Thought bubbles / System Sense | Opt-in, 6s lifetime. | Keep; copy and tone from tokens. |
| 5 | Drag / work-area clamp | Pet can be dragged over taskbar. | Fix via clamp (carried forward). |
| 6 | Expanded chat | Resizes the pet window; position bug. | Fix via separate transparent window (carried forward). |
| 7 | Full work-area toggle | Pseudo-maximize on pet. | Move to chat window; clamp; keep transparency. |
| 8 | Chat send / stream / stop | SSE, cancellation, approval cards. | Keep; fix `[empty response]` via thinking fallback (carried forward). |
| 9 | Scroll wheel | Overlay intercepts. | Fix via ScrollViewer routing (carried forward). |
| 10 | Settings | Editable but duplicate concepts; in-page status exists. | Regroup, relabel, add helper lines, read-only facts. |
| 11 | Customization | Identity editing, persona backup. | Make it the sole ongoing owner of identity. |
| 12 | Brain | Editable raw fields. | Plain tier choice first, raw fields in Advanced; status on page. |
| 13 | Privacy | Disclosure + three deletion actions. | Keep actions; clearer copy and on-page status. |
| 14 | Onboarding (4 screens) | Raw endpoint/provider/agent fields in screen 4; preview handler scope bug. | Plain-language route choice; advanced expander; fix handler scope. |
| 15 | Voice input | Whisper wrapper, language, readiness, opt-in. | Keep local-only design; one owner in Settings; plain onboarding opt-in. |
| 16 | Tier 1 local brain | Qwen bundled, llama.cpp, thinking-disable, fallback. | Keep; disambiguate `reasoning_content`; no new runtime paths. |
| 17 | Tier 2 OpenCode | Service discovery, agents, persona instructions. | Keep; resolve config from `USERPROFILE`/XDG, never hardcode a user path. |
| 18 | Installer / runtime layout | Single-folder app root with `runtime/`. | Keep; docs already specify app-root resolution. |
| 19 | Preflight / readiness | `slop-preflight.ps1` reporter. | Keep; surface readiness in Settings with plain wording. |
| 20 | Tray / autostart | Tray icon, autostart button. | Keep; label from token copy. |
| 21 | Tour / docs / tests | 38-step tour, Pester suites, verify gate. | Update anchors and contracts as part of each change. |
| 22 | Docs: machine paths | Absolute user-home paths in tracked plan docs. | Replace with portable `$HOME` / repo-relative wording. |
| 23 | Docs: Whisper claim | `docs/architecture.md:123` says artifacts are absent; `README.md:114` says bundled; both are tracked. | Correct architecture + plan to match the tracked files. |
| 24 | App data exposure | `data/config.json`, `.bak`, `persona.md` untracked and unignored; contain user state. | Add `/data/` to `.gitignore`; do not touch the files. |
| 25 | Module load order | `Slop.LocalModel.ps1` and `Slop.Route.ps1` dot-sourced twice via Provider. | Remove Provider's duplicate dot-sources; rely on the documented order in `Slop.ps1`. |
| 26 | Repo hygiene drift | `.opencode/` tracked but ignored; referenced `.muted` file absent; old repo-name ignore line. | Keep the tracked config; fix the doc claim; rename the stale ignore line conservatively. |

## Data flow

1. `Slop.Config.ps1` remains the only config writer. No new storage key is introduced.
2. `Slop.Design.ps1` exports pure token lookups; WPF code builds brushes from them. No WPF types in the token module.
3. `Slop.Face.ps1` consumes token palette + scatter parameters; the render loop keeps driving it from the effective signal.
4. Onboarding writes config/persona through the existing `Save-SlopOnboardingResult` path; advanced values remain optional.
5. Settings/Customization/Brain/Privacy keep their per-page status lines; no success message is sent to hidden chat.

## Error handling and accessibility

- Invalid config values stay in-page errors and never write.
- Missing local brain or Whisper artifacts show explicit readiness text; no silent empty reply.
- Chat window construction failure leaves the pet fully interactive.
- Reduced motion freezes particles and springs; status remains legible through colour **and** shape.
- Keyboard focus is visible on all buttons and inputs; dropdowns use dark background/light foreground independent of OS theme.

## Verification

- Focused RED tests for: transparency contract, concept ownership, plain-language labels, advanced disclosure, token contrast, particle count/scatter/freeze, wizard handler scope, per-page status, portable paths, Whisper doc consistency, single dot-source, and `data/` ignore.
- GREEN implementation per bounded task with explicit-path commits.
- Full CI-equivalent Pester suite, tour anchor check, `git diff --check`, review gate, and verify gate with explicit zero failures.
- Live UI checks (user): onboarding choices, settings/customization/brain/privacy flows, expanded/full chat, transparency, scrolling, voice preview, and non-empty replies.

## Acceptance criteria

1. Every concept in the ownership table has one ongoing writable home; other surfaces show facts read-only.
2. First-run no longer requires provider/model/agent knowledge to finish.
3. All primary labels are plain language; advanced strings are behind disclosure with helper text.
4. The pea shows 32 dots with a visibly wider, soft-edged aura and stable frozen state.
5. Compact, expanded, and full-work-area surfaces share one transparent token-driven look; no material API appears in source.
6. Tracked docs contain no machine-specific user paths and make one consistent Whisper claim.
7. `data/` is ignored and untouched; runtime modules are dot-sourced once.
8. Focused RED→GREEN evidence exists for every changed behaviour; all static gates pass with zero failures.
9. No push, tag, release, deploy, or remote change occurs.
