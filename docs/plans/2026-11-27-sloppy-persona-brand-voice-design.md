# Design: Sloppy identity pack and brand consistency audit

Date: 2026-11-27
Status: Design sections approved in brainstorming; written spec pending user
review. Implementation not started.

Note on location: `docs/superpowers/` is gitignored in this public repo, so the
canonical tracked copy of this spec lives in `docs/plans/`, matching the existing
design-doc convention. No local machine paths are part of this design.

## Context

The Full/maximise fix, launcher/shutdown path, control deck, capability toggles,
and Customize fields are already implemented and verified headlessly. The remaining
product requirement is deeper than those mechanics: Sloppy needs its own bundled
persona, instructions, skills/abilities, and personalization inside the installed
app root, and the UI needs a repeatable way to prove brand and voice consistency.

Current gaps:

- `.opencode/opencode.jsonc` loads the companion persona from
  `~/.config/opencode/personality.md`, which is a shared machine-level file rather
  than a Sloppy-owned app-root asset.
- `src/Slop.Onboarding.ps1` generates persona text saying Sloppy has “no tools”,
  while the bundled agent config says OpenCode tools are available.
- `src/Slop.Design.ps1` defines tokens and canonical copy, but the three XAML-heavy
  files contain many literal colours, fonts, radii, and copy strings.
- There is no automated surface-by-surface brand audit.

The user chose the prompt-first identity pack with optional native OpenCode skill
registration, and approved the eight brand checks listed below.

## Goals

- Give Sloppy a tracked, app-root identity pack: persona, instructions, abilities,
  and brand voice rules.
- Keep user personalization in `data/persona.md` without automatically rewriting
  that file.
- Make the resolved identity the system prompt for both OpenCode and local routes.
- Stop the bundled fallback config from depending on a home-directory personality
  file.
- Provide a repeatable audit of every XAML surface and code-created dialog.
- Produce a file:line violation report and an automated gate for brand drift.
- Keep live visual and voice confirmation with the user.

## Non-goals

- No subagents.
- No automatic write, migration, deletion, or reformatting of anything under
  `data/`.
- No overwrite of an active user OpenCode config.
- No dependency on OpenCode native skill discovery for correct Sloppy behaviour.
- No new permission backend; capability toggles remain governed by the existing
  deny-first OpenCode profile system.
- No push, tag, release, deploy, force-push, or repository visibility change.
- No claim by the agent that the rendered UI looks correct.

## Approach rationale

OpenCode documentation states that project skills are discovered from the active
working directory and that `skills` entries resolve relative to the active working
directory, not the config file. Sloppy starts a shared OpenCode service and sends
an inline config through `OPENCODE_CONFIG_CONTENT`, so project-local discovery is
not a reliable source of truth. Native skills are useful when available, but the
companion behaviour must not depend on service working directory or on the user
choosing Sloppy's bundled config.

Therefore the identity pack is prompt-first: tracked app-root Markdown files are
resolved by Sloppy and sent as the system prompt in the request body. OpenCode
native skill registration is optional and additive.

## Architecture

### Tracked app-root files

```text
agent/SLOPPY.md              core persona, voice, boundaries, truthful tool model
agent/abilities/*.md         small reusable behaviour modules
agent/BRAND.md               narrative brand voice and copy rules for the model
src/Slop.AgentPack.ps1       pure resolver; no WPF and no network calls
src/Slop.Design.ps1          machine-readable UI tokens, copy keys, and exceptions
tests/slop-brand-check.ps1      static brand audit gate
tests/slop-brand-baseline.json  accepted baseline of existing violations
docs/brand-audit.md             generated human-readable violation report
```

The installer and app-root packaging must include `agent/`. No tracked file may
contain an absolute machine path.

`agent/BRAND.md` is narrative guidance for the model. `src/Slop.Design.ps1` remains
the machine-readable source of truth for UI colours, typography, spacing, radii,
component style keys, canonical copy keys, and documented exceptions. If the two
disagree, safety and privacy rules win for model behaviour and `Slop.Design.ps1`
wins for UI implementation.

### User-owned file

`data/persona.md` remains the user overlay. It is read when present, capped, and
placed after tracked defaults. It is written only when the user explicitly saves
from Onboarding or Customize. Existing content is not migrated or normalized
automatically.

### Resolver contract

`Get-SlopResolvedAgentPack` returns an object with:

- `Ok`
- `Errors`
- `Warnings`
- `Text`
- `Sources`

Resolution order:

1. `agent/SLOPPY.md`
2. `agent/abilities/*.md`
3. `agent/BRAND.md`
4. config identity: name, owner name, colour, personality preset
5. `data/persona.md` as user overlay

Rules:

- The resolved system prompt is capped at 8000 characters.
- Missing ability modules are skipped with a warning.
- A missing or malformed tracked core file is a hard failure; no request is sent
  with a partially resolved identity.
- A malformed user overlay is treated as plain user text, capped, and reported as a
  warning.
- Tracked defaults must not contain credentials, private-key material, absolute
  filesystem paths, or home-directory references.
- User text is marked as user customization and cannot remove safety, privacy,
  permission, or truthfulness rules.
- The resolver is pure and testable without WPF, OpenCode, or a running service.

### Runtime data flow

`src/Slop.ps1` currently reads the persona immediately before calling
`Get-SlopStreamPlan`. That call becomes `Get-SlopResolvedAgentPack`, and the
resolved `Text` is passed as `PersonaText`.

`src/Slop.Route.ps1` continues to pass `PersonaText` into
`New-SlopChatRequestBody`, which creates the `system` message. Both OpenCode and
local routes therefore receive the same resolved Sloppy identity without changing
the bridge protocol.

### OpenCode fallback config

The bundled `.opencode/opencode.jsonc` stops referencing
`~/.config/opencode/personality.md`. Its `sloppy` agent `system` value becomes a
stable instruction that expects the companion persona supplied in the request.

`Sync-SlopOpenCodeConfig` may add an absolute, runtime-resolved path to the
app-root abilities directory in the generated service config. This path is runtime
state, never tracked content. The existing precedence rule remains: a user's active
config wins, and the bundled fallback is installed only when the service env config
is empty.

## Identity pack contents

### Core persona

`agent/SLOPPY.md` defines Sloppy as a warm desktop companion: concise, dryly funny,
affectionate without being clingy, genuinely deep when needed, honest about tools
and limits, local-first, and never corporate or pretend-human. It explicitly states
that tools are available through OpenCode only with the permissions shown to the
user.

### Ability modules

Each ability is a short Markdown file with one purpose:

- `companion-voice.md` — tone, brevity, warmth, and dry wit.
- `local-first.md` — no cloud account, no telemetry, loopback-only service model.
- `permission-translation.md` — explain Allow, Allow once, Reject, and destructive
  actions in plain language.
- `workspace-helper.md` — inspect, edit, and create local files only with the
  configured permissions; report honestly.
- `research-on-demand.md` — use web search and fetch when it genuinely helps.
- `shutdown-safety.md` — confirm consequential actions and use the shared clean
  shutdown path.

The first implementation does not make these OpenCode-native skills load-bearing.
They are Sloppy ability cards consumed by the resolver. Native registration can be
added later without changing the prompt contract.

### Personalization

Existing Customize fields remain the user-facing controls: name, owner name,
colour, personality preset, and persona text. Colour affects the pet and UI
identity marks; it does not weaken status/accessibility roles. Personality presets
select the existing calm/playful/curious/professional voice samples. Persona text
is the user overlay and is appended after tracked defaults.

## Brand and voice consistency audit

### Surfaces

The audit covers:

- main pet window in `src/Slop.ps1`
- chat window in `src/Slop.ChatWindow.ps1`
- six control-deck sections
- Settings, Customize, Brain, and Privacy panels
- four onboarding screens in `src/Slop.Onboarding.ps1`
- dialogs created in code, including disclosure and shutdown confirmation

### Checks

1. **Surface inventory** — parse all XAML here-strings and enumerate code-created
   dialogs; report every surface with its file and line range.
2. **Token coverage** — scan `Background`, `Foreground`, `BorderBrush`, `Fill`,
   `Stroke`, `FontSize`, `CornerRadius`, and `Margin`. A literal is valid only when
   it comes from a shared style, a token-derived resource, or a documented
   exception.
3. **Copy coverage** — scan `Text`, `Header`, `Content`, and `ToolTip`. User-facing
   static copy must map to a canonical key or a documented exception. Raw values,
   provider IDs, user-entered text, and legal text are exceptions with reasons.
4. **Component parity** — validate one style contract for primary, secondary, and
   danger buttons; inputs; checkboxes; combos; cards; headers; and status text.
   Resource names and token-derived values must match across surfaces.
5. **State coverage** — verify hover, disabled, focus, error, success, thinking,
   and needs-you states where the component or status role requires them.
6. **Accessibility math** — compute contrast ratios, minimum font sizes, and
   hit-target sizes from tokens and declared control dimensions.
7. **Automated gate** — `tests/slop-brand-check.ps1` emits a file:line violation
   report, compares it with `tests/slop-brand-baseline.json`, and fails on new
   violations or hard accessibility/copy failures.
8. **Optional live inventory** — enumerate windows and controls through UIA and
   capture screenshots for user review. This is evidence for the user, not an agent
   visual claim.

### Component style contract

`src/Slop.Design.ps1` gains named style roles such as `slop.button.primary`,
`slop.button.secondary`, `slop.button.danger`, `slop.input`, `slop.checkbox`,
`slop.combo`, `slop.card`, `slop.header`, and `slop.status.*`, each tied to token
names. XAML surfaces may keep local resources, but each local resource must carry
the canonical name and token-derived values. A shared resource dictionary is not
required for this design.

### Exceptions and ratchet

The first audit is a baseline. Existing violations are recorded with a reason and
severity rather than forcing one unreviewable UI rewrite. The gate fails when:

- a new hardcoded colour, font, radius, spacing, or copy literal appears;
- a canonical style resource is missing or drifts from its token contract;
- contrast, font size, or hit-target math fails;
- an exception is added without a reason;
- an absolute machine path or credential-like string appears.

Remediation then reduces the baseline surface by surface. Colours for the pet face,
particles, silhouette, and status glyphs may remain literal when they are semantic
art marks and are listed as exceptions.

### Report format

`docs/brand-audit.md` contains a table with columns: surface, file, line, rule,
value, severity, and exception reason. A summary lists counts by surface and rule,
the accepted baseline count, and the remaining violations after each remediation
step.

## Error handling

- Resolver hard failure: show a clear error bubble, keep the previous conversation
  state, and send no request with an unresolved identity.
- Missing ability module: skip it, add a warning to the resolver result, and leave
  the audit note in the report; do not crash.
- Overlong persona overlay: reject the save in Customize with a specific message;
  never silently truncate persisted user text.
- OpenCode config sync failure: preserve the active config and report failure; do
  not fall back to an older embedded config.
- Brand audit parse failure: fail the gate with the surface and parser error.
- Live UIA inventory failure: report it as unavailable; it never replaces the
  static gate.

## Testing

Identity pack tests verify:

- all tracked identity files are present and included by packaging checks;
- resolution order and precedence;
- missing and malformed tracked files;
- missing, malformed, and overlong user overlays;
- prompt cap and no NUL/control characters;
- no credentials, private keys, absolute paths, or home-directory references in
  tracked defaults;
- OpenCode and local request bodies contain the resolved system prompt;
- fallback config contains no home-directory personality reference;
- an active user config is never overwritten.

Brand audit tests verify:

- every expected surface is discovered;
- token and copy scans produce file:line findings;
- component style roles are present and consistent;
- state triggers are present where required;
- contrast, font-size, and hit-target math is deterministic;
- baseline comparison fails on new violations and hard failures;
- generated report matches the machine-readable findings.

All changes must pass the canonical verify gate, tour anchor check, review gate,
and `git diff --check` before being called complete.

## Acceptance criteria

- Sloppy ships its own app-root identity pack and uses it on every request.
- User personalization still works through existing config fields and
  `data/persona.md`.
- Existing `data/` content is unchanged unless the user explicitly saves.
- Bundled OpenCode config no longer depends on a home-directory personality file.
- `tests/slop-brand-check.ps1` produces a readable report and a stable gate.
- Every current brand violation is either fixed, baselined with a reason, or
  classified as a hard failure for remediation.
- The user receives a manual visual and voice checklist; the agent makes no live
  appearance claim.

## Phasing

Implementation is split into two bounded plans after this spec is approved:

1. **Identity Pack** — tracked assets, resolver, request wiring, fallback config,
   packaging, and tests.
2. **Brand + Voice Audit** — audit script, baseline report, ratchet gate, then
   surface-by-surface remediation.

No implementation starts until the user approves the written spec and a plan is
created for phase 1.

## Risks and trade-offs

- **Prompt bloat** — ability cards must stay short; the 8000-character cap prevents
  silent context growth.
- **User override conflict** — user text is lower priority than safety and privacy
  rules; the saved overlay is not automatically rewritten.
- **Native skill fragility** — optional registration can help power users but is
  not required for correct Sloppy behaviour.
- **Large UI baseline** — ratcheting avoids a giant blind refactor but leaves known
  violations visible until phase 2 remediation reduces them.
- **WPF state coverage** — some states are provided by default WPF templates; the
  audit must distinguish declared states from assumed defaults and report both.
