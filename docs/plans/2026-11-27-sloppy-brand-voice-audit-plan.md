# Plan: Sloppy brand and voice consistency audit (phase 2)

Date: 2026-11-27
Status: Validated 2026-11-27 — 1 fenced PowerShell block parsed with 0 errors;
0 machine paths and 0 unresolved marker tokens; code dialog anchor confirmed at
`src/Slop.ps1:1972`; aggregator glob confirmed; all 5 contrast pairs pass 4.5:1;
all referenced design tokens exist. Ready for inline execution on `main`.
Spec: `docs/plans/2026-11-27-sloppy-persona-brand-voice-design.md` (approved 2026-11-27).

## Scope

Build a repeatable, headless brand + voice audit for the existing Sloppy UI. This
phase produces an **inventory, a machine-readable baseline, a human-readable report,
and a ratchet gate**. It does **not** redesign the UI or rewrite existing copy.

Non-goals:

- no changes to product XAML, runtime behaviour, or `data/`
- no UIA/screenshot capture in the agent's verification claims (optional live
  inventory is a user-run evidence step only)
- no push, tag, release, deploy, visibility change, or force-push
- no claims about live visual appearance or spoken voice

## Files

| File | Role |
| --- | --- |
| `src/Slop.BrandAudit.ps1` | new pure module: surface discovery, scans, baseline compare, report string |
| `src/Slop.Design.ps1` | gains named component style roles tied to existing tokens |
| `tests/slop-brand-check.ps1` | new Pester suite; auto-discovered by `tests/Slop.Tests.ps1` |
| `tests/slop-brand-baseline.json` | generated accepted findings with reason + severity |
| `docs/brand-audit.md` | generated report: table, counts, voice profile, ratchet status |
| `docs/plans/2026-11-27-sloppy-brand-voice-audit-plan.md` | this plan |

`tests/slop-hygiene-check.ps1` already covers absolute machine paths and credential
hygiene; the audit does not duplicate that gate.

## Audit design

### Surface discovery (`Get-SlopBrandSurfaces`)

Scan these tracked files in order: `src/Slop.ps1`, `src/Slop.ChatWindow.ps1`,
`src/Slop.Onboarding.ps1`, `src/Slop.ControlDeck.ps1`, `src/Slop.Disclosure.ps1`,
`src/Slop.Shutdown.ps1`.

- A here-string opens on a line containing `@'` or `@"`; it closes on a line whose
  trimmed value is exactly `'@` or `"@`. Verify with the probe already used in this
  session (it found 3 XAML surfaces: Slop.ps1 37-379, ChatWindow 81-284,
  Onboarding 67-203).
- A here-string whose body contains `<Window` is a `Xaml` surface with 1-based
  `StartLine`/`EndLine`.
- Code-created dialogs are found by scanning for
  `[System.Windows.Window]::new()` and `[System.Windows.MessageBox]::Show`, reported
  as `Code` surfaces with the file and line. The disclosure dialog in `Slop.ps1`
  (~line 1972) must be discovered.
- Every expected surface must be discovered or the gate fails (spec: parse failure
  fails the gate).

### Findings (`Get-SlopBrandFindings`)

Each finding is `[pscustomobject]` with stable fields:
`Surface, File, Line, Rule, Value, Severity, Reason`.

Stable key: `File|Line|Rule|Value` (normalized: trimmed, CRLF-safe, no machine paths).

Rules:

1. `token.literal` — `Background`, `Foreground`, `BorderBrush`, `Fill`, `Stroke`,
   `FontSize`, `CornerRadius`, `Margin` literal that is neither:
   - a `{StaticResource ...}` / `{DynamicResource ...}` / `{TemplateBinding ...}`
     expression, nor
   - a value present in `$script:SlopDesignTokens.Values`, nor
   - one of the allowed named literals: `Transparent`, `Auto`, `*`.
   Semantic art marks are a documented exception class: elements whose `x:Name`
   contains `Glyph`, `StatusDot`, `BodyPath`, `HeadHighlight`, or particle/face
   names keep their literals with reason `semantic art mark` (spec §Exceptions).
2. `copy.literal` — literal `Text`, `Header`, `Content`, `ToolTip` value not equal
   to a value in `$script:SlopDesignCopy` and not a documented exception:
   data-binding expressions, user-entered placeholders (`...`, `Say something...`),
   provider IDs/model IDs, glyph-only controls (`X`, `☰`, `□`, `🎤`), legal/terms
   copy, and numbers/counts.
3. `copy.voice` — literal user-facing copy containing a phrase banned by
   `agent/BRAND.md`: corporate ceremony, fake intimacy, human pretend-play,
   filler praise/apology/restated premise. Deterministic regex list in the module,
   sourced from BRAND.md lines 3-13. No match should be required for a passing
   baseline; a new match is a violation.
4. `style.role.missing` — a required component role key is absent from
   `src/Slop.Design.ps1` (see below). Severity `hard`.
5. `style.role.drift` — a role's `Token` points to a token name that does not exist,
   or its `Min`/`Max` values disagree with the token. Severity `hard`.
6. `contrast.fail` — a declared text-on-surface pair from
   `$script:SlopBrandContrastPairs` computes below 4.5:1 via the existing
   `Test-SlopContrast`. Severity `hard`.
7. `type.floor` — a declared `FontSize` literal below token `type.floor` (11),
   excluding glyph-only controls and documented compact captions. Expected to be
   all-baselined or empty with current source.
8. `hit-target.small` — a declared `Button` `Width`/`Height` below the 24px token
   floor for non-chrome controls. Compact chrome dots are a documented exception.
9. `path.absolute` / `credential.like` — absolute machine path or credential-like
   string inside a tracked surface. Severity `hard`. (Hygiene suite is the primary
   gate; this is defence in depth.)

### Component style roles (tasks 3-4)

Add to `src/Slop.Design.ps1` a `$script:SlopBrandStyleRoles` ordered map with roles:
`slop.button.primary`, `slop.button.secondary`, `slop.button.danger`, `slop.input`,
`slop.checkbox`, `slop.combo`, `slop.card`, `slop.header`, `slop.status.idle`,
`slop.status.thinking`, `slop.status.working`, `slop.status.success`,
`slop.status.error`. Each role carries `Token`, `TextToken`, and optional
`MinSize`. Values must reference existing token names only. A new accessor
`Get-SlopStyleRole -Name <role>` returns the role or throws.

XAML surfaces may keep local resources; the spec explicitly does not require a
shared resource dictionary. This phase validates the contract exists and is
consistent, not that every XAML element uses it.

### Accessibility math

Reuse `Get-SlopLinearChannel`, `Get-SlopRelativeLuminance`, and `Test-SlopContrast`
from `Slop.Design.ps1` — do not write a second contrast implementation. Declare the
pairs explicitly in the audit module (text.primary/surface.app,
text.secondary/surface.panel, text.subtle/surface.app, each status.text.*/surface.app,
white/fill.primary, white/fill.destructive). Deterministic, no WPF types.

### Baseline and gate

`Compare-SlopBrandBaseline -Findings <list> -BaselinePath <path>` returns
`{ Ok, New, MissingReason, Stale, Errors }`:

- `Ok` is true only when every current finding has a baseline entry with a non-empty
  `Reason`, there are no `hard` findings, and no new keys appeared.
- `New` = finding key not in baseline → gate failure.
- `MissingReason` = baseline entry with empty `Reason` → gate failure.
- `Stale` = baseline key no longer present → informational; report it so the next
  remediation step can prune the baseline deliberately.
- Baseline entries store `Reason` and `Severity`; generated reasons are per-rule
  defaults (e.g. `legacy token literal; reduce surface by surface`) and are clearly
  marked in the report as ratchet entries, not as approval.

`New-SlopBrandReport` returns markdown with the required columns
`surface | file | line | rule | value | severity | exception reason`, plus counts by
surface/rule, accepted baseline count, hard-failure count, stale count, and a
source-backed voice profile section using the schema from `brand-voice` (Author,
Goal, Confidence, Source Set, Rhythm, Compression, Capitalization, Parentheticals,
Question Use, Claim Style, Preferred Moves, Banned Moves, CTA Rules, Channel Notes).
Source set: `agent/BRAND.md`, `agent/SLOPPY.md`, `agent/abilities/*.md`, and
`$script:SlopDesignCopy`. Channel notes derived from those sources only — no
invented social voice.

### Optional live inventory

Not implemented in this plan. If the user wants it later, it must be a separate,
user-run script that writes evidence files; the agent never claims visual truth
from it.

## Tasks

Each task is RED→GREEN with explicit-path commits only. No `git add -A`.

### Task 1 — RED: brand audit contract

Create `tests/slop-brand-check.ps1` (Pester 6, discovered by
`tests/Slop.Tests.ps1`). Assert:

- module file exists; `Get-SlopBrandSurfaces`, `Get-SlopBrandFindings`,
  `Test-SlopBrandContrast`, `Compare-SlopBrandBaseline`, `New-SlopBrandReport`,
  `Test-SlopBrandGate`, and `Get-SlopStyleRole` are exported;
- real-source discovery finds 3 XAML surfaces and the disclosure code dialog;
- a seeded temp fixture with a literal colour, a banned voice phrase, and a small
  hit target produces findings with `File:Line` and the expected rules;
- contrast math returns known values for two fixed pairs;
- baseline compare fails on a new key, passes when all findings are baselined with
  reasons, fails on an empty reason, and reports stale entries;
- report contains the required table columns and a row per finding;
- the report includes a source-backed voice profile section.

Real baseline/report file assertions are deliberately deferred to Task 5 so this
suite can reach green after Task 2 without generated artifacts.

Commit RED. Expected: failures from the missing module.

### Task 2 — GREEN: pure audit module

Implement `src/Slop.BrandAudit.ps1` per the design above. Dot-source
`src/Slop.Design.ps1` for tokens, copy, and contrast. No WPF types, no network, no
`$args`, no machine paths. Commit GREEN; Task 1 suite must be fully green first.

### Task 3 — RED: component style role contract

Extend `tests/slop-brand-check.ps1` with assertions that every required role exists,
that `Get-SlopStyleRole` throws on an unknown role, and that each role's `Token`
and `TextToken` resolve to existing tokens. Commit RED.

### Task 4 — GREEN: style roles in the design module

Add `$script:SlopBrandStyleRoles` and `Get-SlopStyleRole` to
`src/Slop.Design.ps1`. Commit GREEN. Re-run Tour check afterwards: line additions in
`Slop.Design.ps1` may shift step anchors; recompute only if the check reports drift.

### Task 5 — RED/GREEN: baseline and generated report

RED: add assertions that `tests/slop-brand-baseline.json` parses, every current
finding has an entry with a non-empty reason, and `docs/brand-audit.md` contains the
accepted count and all required columns.

GREEN: generate both artifacts from the module against the real repository. Include
a short “ratchet, not approval” note in the report. Commit the two generated files
with explicit paths.

### Task 6 — Gate integration check

Confirm `tests/Slop.Tests.ps1` discovers `slop-brand-check.ps1` (it globs
`*-check.ps1`, so no edit should be needed). Run the focused suite and record the
count. If discovery does not happen, fix the aggregator in its own RED/GREEN pair.

### Task 7 — Final gates

Run, in order:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-brand-check.ps1 -Output Normal"
pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-tour-check.ps1 -Output Normal"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\verify.ps1"
pwsh -NoProfile -File "$env:USERPROFILE\.agents\scripts\review.ps1"
git diff --check
git status --short
git rev-list --left-right --count origin/main...HEAD
```

Expect: focused suite green, tour 38/0, canonical verify `Failed: 0` with exit 0,
review exit 0 with no unresolved marker comments, diff check silent, clean tree,
0 behind origin.

## Acceptance criteria

- `tests/slop-brand-check.ps1` emits a file:line violation report and a stable gate.
- Every current violation is fixed, baselined with a reason, or classified hard.
- The report matches the machine-readable findings and includes a voice profile.
- All final gates pass.
- The user receives a manual visual/voice checklist; no live appearance claim.

## Risks and trade-offs

- **Large baseline** — roughly 800 attribute occurrences exist across three XAML
  surfaces. Baselines will be sizeable; the ratchet is the point, and remediation
  is deliberately deferred surface by surface.
- **Heuristic parsing** — line-based XAML here-string scanning is simpler than a
  full XML parser and cannot validate XAML semantics. It is deterministic and
  sufficient for token/copy coverage; parse failures fail closed.
- **False positives in copy** — user-entered placeholders, provider IDs, and legal
  copy are exceptions. If a finding is wrong, fix the exception rule with a reason
  rather than weakening the gate.
- **Voice source set** — `agent/BRAND.md` is short. The profile must stay
  source-backed and must not invent a social-media voice.
