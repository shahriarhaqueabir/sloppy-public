# Test Plan — Sloppy Product Experience

**Date:** 2026-11-27
**Spec:** `docs/plans/2026-11-27-product-experience-design.md`

## Protocol

Every behavior change follows RED→GREEN:

1. Write or extend the assertion first.
2. Run it and capture the expected failure (exact failing assertion and count).
3. Commit the RED test on an explicit path with a `test:` message.
4. Implement the minimum change.
5. Run the same assertion to green, then the focused suite.
6. Commit source on explicit paths with a `feat:`/`fix:` message.

Never lock a RED test whose numbers contradict the stated semantics. Sanity-check day/count/radius values against the implementation boundary before committing RED.

## Test inventory

| Suite | Status | New coverage |
|---|---|---|
| `tests/slop-design-check.ps1` | New | Token resolution, copy keys, WCAG contrast, no WPF types, no duplicate literal. |
| `tests/slop-face-check.ps1` | Extend | 32 dots, radius 0.46, size <= 2.6, frozen determinism, [0,1] clamp, 24 patterns intact. |
| `tests/slop-transparency-check.ps1` | New | Chat XAML contract, forbidden material APIs, work-area clamp, ScrollViewer routing, failure isolation. |
| `tests/slop-shell-check.ps1` | Extend | Concept ownership, plain labels, Advanced expanders, in-page status, wizard handler scope. |
| `tests/slop-motion-check.ps1` | Extend | Reduced-motion freeze, spring cadence unchanged. |
| `tests/slop-opencode-check.ps1` | Keep | No change; needs live service, excluded from CI. |
| `tests/slop-tour-check.ps1` | Keep | Anchor resolution after T7. |

All `*-check.ps1` files are discovered by `tests/Slop.Tests.ps1` and by the CI command. Avoid `-Output None`; it can hide container discovery failures.

## Coverage map

| Spec acceptance criterion | Test |
|---|---|
| One writable home per concept | `slop-shell-check.ps1` static ownership assertions. |
| Plain-language first-run | `slop-shell-check.ps1` label assertions on onboarding + settings. |
| Advanced disclosure | `slop-shell-check.ps1` expander presence assertions. |
| 32-dot soft aura, stable freeze | `slop-face-check.ps1`. |
| Transparent token-driven surfaces | `slop-transparency-check.ps1` + `slop-design-check.ps1`. |
| Portable paths, consistent Whisper claim | repo hygiene static assertions in T6 tests. |
| `data/` ignored and untouched | `.gitignore` assertion + `git status` check. |
| Single dot-source | `slop-shell-check.ps1` load-order assertion. |
| No remote change | `git status` / `git rev-list` check in verify plan. |

## Fixtures and isolation

- Pure modules are dot-sourced directly; no WPF window is constructed in headless suites except where a type-only check is needed.
- No live OpenCode service, microphone, model download, or network access in headless tests.
- Temporary files go under `$env:TEMP\opencode` (pre-created and approved), never inside `data/`.
- No credential or personal value is written to a fixture. Use placeholders only.

## Live tests handed to the user

The agent does not claim these. Provide a short checklist:

1. First-run onboarding: finish without provider/model/agent knowledge; Advanced expander works.
2. Settings, Customization, Brain, Privacy: edit, save, see in-page confirmation.
3. Pea: wider aura, reduced-motion freeze, signal colour/shape.
4. Expanded and full-work-area chat: transparent, scrollable, clamped to work area, non-empty reply.
5. Voice opt-in and preview (requires real Whisper artifacts).
6. Drag, tray, autostart.

## Exit criteria

- Every RED assertion was observed failing before GREEN.
- Full CI-equivalent suite passes with `Failed: 0` and no discovery errors.
- Tour check, diff check, verify ritual, and review ritual pass.
- Live checklist is handed to the user without an agent claim.
