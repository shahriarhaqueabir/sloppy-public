# Review Plan — Sloppy Product Experience

**Date:** 2026-11-27
**Spec:** `docs/plans/2026-11-27-product-experience-design.md`
**Companion plans:** implementation, verify, test (same date prefix).

## Purpose

Catch correctness, security, and maintainability defects before a task is considered done. Review is advisory but a P0 or P1 finding blocks progress until resolved or explicitly recorded as deferred with a reason.

## When review runs

1. After every task commit in the implementation plan (T1–T7).
2. After the final gate run, before any handoff.
3. On demand after a fix to a previously reviewed file.

## Commands

Repo-local review gate (portable, from repo root):

```powershell
git diff --check
git status --short
```

Canonical review ritual (machine-local, used when available):

```powershell
& "$HOME/.agents/scripts/review.ps1"
```

If the ritual path is unavailable, use `git diff --check` plus the focused test command for the changed area and record the substitution in the work log. Never claim the ritual ran when it did not.

## Review checklist

### Correctness

- Does the change implement the exact RED contract, no more and no less?
- Are pinned values (32 dots, 0.46 radius, 2.6 max size, 96x96 region, inset 4) present in both source and test?
- Does every changed handler still bind in the correct scope?
- Are config reads/writes still routed through `Slop.Config.ps1`?
- Does the chat window still leave the pet interactive on failure?

### Security and privacy

- No credential, token, or password value in source, tests, docs, or commit messages.
- No machine-specific user path in tracked files: no user-profile path, project-drive root, or hard-coded temp directory.
- No contents of `data/` staged, printed, or referenced by a test fixture.
- Loopback-only base URL validation still holds.
- Permission grants unchanged unless the spec explicitly authorises them.

### Maintainability

- One writable home per concept from the ownership table; other surfaces read-only.
- No new duplicate colour/copy literal outside `Slop.Design.ps1`.
- No duplicate dot-source of a runtime module.
- New functions follow existing `Get-/New-/Update-/Test-/Set-` naming.
- Tour anchors and inline line refs still match source after line shifts.

### Behavior preservation

- Existing config v2 schema unchanged; no migration added.
- Tier 1/Tier 2 selection logic unchanged.
- 24 face patterns still validate; no pattern removed.
- Signal resolver semantics unchanged.
- No push, tag, release, deploy, or visibility change.

## Severity rubric

| Level | Meaning | Action |
|---|---|---|
| P0 | Data loss, credential leak, broken core flow, or red full gate. | Stop immediately; fix before any further task. |
| P1 | Wrong ownership, machine path in tracked file, contract mismatch, stale anchor. | Fix before the next task. |
| P2 | Duplicate literal, unclear label, doc drift, minor naming inconsistency. | Fix in the same task or record with a reason. |
| P3 | Cosmetic or optional cleanup with no behavior impact. | Record; may defer to the end. |

## Evidence format

For each review, append to `.memory/2026-11-27-sloppy-worklog.md`:

```
- <time> — Review T<n>: <command> exit <code>; findings P0=<n> P1=<n> P2=<n> P3=<n>; decision=<fixed|deferred:reason>.
```

## Stopping rule

Three attempts at the same finding without resolution means stop and report with the exact error and the options. Do not guess a fourth fix.
