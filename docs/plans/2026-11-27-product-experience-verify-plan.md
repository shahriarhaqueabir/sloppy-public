# Verification Plan — Sloppy Product Experience

**Date:** 2026-11-27
**Spec:** `docs/plans/2026-11-27-product-experience-design.md`

## Principle

Command output is the only evidence. A green count from a truncated run, a skipped container, or an `-Output None` invocation is not proof. Read failure lines and explicit `Failed:` counts.

## Gate order

Run in this order; stop on the first failure.

### 1. Focused test for the changed task

From the implementation plan task table. Example:

```powershell
pwsh -NoProfile -File tests/slop-face-check.ps1
```

Expected: zero failures and the pinned assertions from the RED contract present in source.

### 2. Full CI-equivalent Pester suite

Matches `.github/workflows/ci.yml` exactly (from repo root):

```powershell
Import-Module Pester -MinimumVersion 6.0
$paths = Get-ChildItem -Path tests -Filter '*-check.ps1' |
  Where-Object { $_.Name -ne 'slop-opencode-check.ps1' } |
  Select-Object -ExpandProperty FullName
Invoke-Pester -Path $paths -CI -Output Detailed
```

Expected: `Failed: 0`, no discovery/container errors, no skipped suites caused by registration failure. Record the pass count.

Note: `slop-opencode-check.ps1` is excluded by CI because it needs a live service. Include it only when the user authorises a live probe.

### 3. Tour anchor check

```powershell
pwsh -NoProfile -File tests/slop-tour-check.ps1
```

Expected: every step's file and line anchor resolves, zero failures. If source line shifts moved anchors, refresh them in a separate tour-only commit and rerun.

### 4. Static diff and status

```powershell
git diff --check
git status --short
```

Expected: `git diff --check` silent; status shows only intended paths and the pre-existing `?? data/`.

### 5. Privacy scan

```powershell
git grep -n -E 'C:\\Users\\shahr|E:\\Projects\\|AppData\\Local\\Temp' -- .
git grep -n -E 'MicaController|AcrylicBrush|BackdropType|DwmSetWindowAttribute|SetWindowCompositionAttribute' -- .
git grep -n -E 'password|token|api[_-]?key' -- src tests docs
```

Expected: no machine paths in tracked files; no material APIs in tracked source; credential-word hits are variable names or documentation, never values.

### 6. Canonical verify ritual

```powershell
& 'C:\Users\shahr\.agents\scripts\verify.ps1'
```

Expected: exit code 0 and `All gates passed`. If unavailable, substitute the repo CI command and record the substitution.

### 7. Review ritual

```powershell
& 'C:\Users\shahr\.agents\scripts\review.ps1'
```

Expected: exit code 0 or findings recorded per the review plan.

## Failure policy

1. Read the full error output; never claim success on a warning or error.
2. Identify the smallest failing unit and reproduce it directly.
3. Fix, rerun the focused gate, then restart the gate order from step 2.
4. Three failures on the same issue means stop and report with exact output and options.

## Evidence record

Append to `.memory/2026-11-27-sloppy-worklog.md` after each full run:

```
- <time> — Gates: focused <pass>/<fail>; CI <pass>/<fail>/<skip>; tour <pass>/<fail>; diff <exit>; privacy <hits>; verify <exit>; review <exit>.
```

## Deferred by design

The following are explicitly not verified by the agent and must be checked by the user:

- Live WPF appearance, transparency, animation smoothness, and particle aesthetics.
- Real onboarding and settings interactions with a live OpenCode service.
- Real Whisper transcription and microphone input.
- ISCC installer compile and release assets.

Do not convert a static pass into a live claim.
