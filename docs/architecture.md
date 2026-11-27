# S.L.O.P. Architecture

Status: accepted 2026-11-22; current as of 2026-11-23 (companion-life slice). Supersedes the earlier local-only inference design in this file.
Deciders: the user. Scope: the whole product, not a single feature.

**Current state:** the face, lifecycle, OpenCode bridge, `sloppy` agent, safety tripwire,
in-chat approvals, spring-membrane visual shell, nine-phase idle life, opt-in System
Sense and the resizable/maximizable expanded screen are implemented and verified.
Headless suites, the verify gate and the live pixel/UIA verifier are green. Phase 3
(MCP servers) and Phase 4 (workflows/reminders/settings) remain planned. See
`docs/decisions/2026-11-23-project-retrospective.md` for the decisions and operating rules.

This document is the combined architecture and decision record. It replaces the old
"Slop owns the tools" design recorded previously in this file and in
`docs/product-direction.md`.

---

## Decision record

### Context

The requested product has five capabilities: companion (conversation, memory,
personal context, reminders), knowledge assistant (notes, documents, file search),
research assistant (web search, browser, sourced answers), PC operator (launch apps,
manage files, approved commands), and workflow assistant (multi-step tasks).

A conventional implementation would build all five inside Slop: a tool registry, a
permission engine, a memory database, a web-search client, Playwright integration,
Windows UI Automation, and a workflow engine. Slop is a PowerShell 7 + WPF app whose
box is already crowded with window management, a custom renderer, and streaming UI.
That approach duplicates a large amount of existing, better-maintained infrastructure.

OpenCode is already a local-first agent harness with a tool system, ordered
allow/ask/deny permissions, MCP servers, persistent sessions, agents, commands,
skills, web search, shell and PTY execution, and a structured event stream. Local
config confirms `agents`, `commands`, `mcp` and `permissions` blocks are already in
use, with 12 global agent files and 20 commands. OpenCode v2.3.2 exposes these over
an HTTP API.

### Decision

Slop is the **face**. OpenCode is the **brain and hands**.

Slop keeps the pea, its visual language, the chat surface, and the input box. It does
not implement tools, permissions, memory storage, web search, browser automation, or
workflow orchestration. A thin bridge connects Slop's existing streaming request path
to `opencode serve`, translating OpenCode events into the deltas and signals Slop
already understands.

Tool and permission behaviour is configured in `opencode.jsonc` and MCP servers —
not written in PowerShell.

### Alternatives considered

**1. Build the five-capability tool system inside Slop.**
- Pros: no external runtime dependency; full control over every tool.
- Cons: duplicates OpenCode almost feature for feature; PowerShell is a poor home for
  Playwright, UI Automation and web search; a second permission engine is a second
  security surface to audit; months of work before the first useful capability.
- Why not: the capabilities are commodity infrastructure, and Slop's differentiator is
  the character and its visual language, not the tool registry.

**2. Connect Slop to OpenCode (chosen).**
- Pros: all five capabilities arrive at once; permissions and activity logging come
  for free; local-first by default; adding a capability is an MCP server or a Markdown
  agent, not a new subsystem.
- Cons: OpenCode must be running; several API routes are marked experimental; the
  default agent prompt is coding-oriented; a translation layer is required.
- Why: largest capability gain for the smallest amount of new code, and every
  downside is isolated in one adapter file or fixable with config.

**3. Fully local custom assistant (local model, own memory and automation).**
- Pros: maximum independence and privacy.
- Cons: model capability and hardware become the ceiling; still requires building the
  entire tool and permission stack.
- Why not: OpenCode can be configured with local providers too, so this buys little
  beyond what option 2 already offers.

**4. Rewrite Slop in TypeScript around `@opencode/sdk`.**
- Pros: in-process host, no network hop, access to plugins and transforms.
- Cons: loses the existing WPF character renderer and the verified live verifier;
  effectively a rewrite of the whole UI.
- Why not: viable later as a different frontend, not as the path to these capabilities.

### Consequences

Positive: capability coverage jumps from "chat with a local model" to a full agent
harness; safety policy lives in one place; adding tools is configuration; OpenCode's
session history replaces a bespoke chat database.

Negative: Slop no longer works standalone — it needs `opencode serve`; the visual
language can only express what its four shapes and four colours already encode;
OpenCode's event schema is still evolving.

Risks: experimental route churn (mitigation: isolate all API calls in the bridge
adapter); coding-flavoured replies (mitigation: a dedicated `companion` primary agent
with a persona system prompt); cloud cost and privacy (mitigation: provider and model
are per-session config, so local stays the default).

---

## Runtime topology

```
Slop (WPF, pwsh -STA)
  pea + bubble + input + signals
        │  route decision
        ├─ local (Tier 1) ── llama.cpp b12676 ── Qwen3.5-2B Q4_K_M (LFS-tracked GGUF)
        │   localhost:18080, model + optional mmproj, ctx 8192/16384/32768
        │
        ▼
Slop.Lifecycle.ps1  ── phases, timestamps, generation guard, SSE parsing, errors
        │
        ▼
Slop.OpenCode bridge  ── session create, prompt, event translation
        │  HTTP + SSE
        ▼
opencode serve --port 28894 (Basic auth; password from ~/.config/opencode/service.json)
  sessions · agents · tools · permissions · MCP · websearch · events
```

Tier 1 runs locally through `runtime/llama-b12676-bin-win-cuda-13.5-x64/llama-server.exe` and the LFS-tracked `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` (1.3 GB, Apache-2.0); `--jinja` uses the GGUF's embedded chat template. An mmproj is optional and unused by default. HF download cache under `runtime/models/.cache/` is ignored. Text requests use the existing llama.cpp adapter. Opt-in voice input records a short WAV with WinMM; the Whisper CLI and DLLs are bundled under `runtime/whisper/`. `ggml-small.bin` is downloaded and checksum-verified during setup, so the bundled Whisper small setup is complete. `src/Slop.Audio.ps1` transcribes locally and sends the transcript through the same text path. No audio leaves the machine, and there is no TTS or VAD. `mmproj` and `localVisionReady` stay unused readiness hooks; Tier 1 makes no image claim.

The bridge creates **one OpenCode session per Slop conversation** and sends only new
user text on each turn. Slop must stop resending its 12-message history — OpenCode
already owns that context.

Connection options:

| Option | Verdict |
|---|---|
| `opencode serve` HTTP + `GET /api/event` SSE | **Chosen.** PowerShell-native, reuses the existing SSE parser, cancellable via `POST /session/{id}/interrupt`. |
| `@opencode/sdk` embedded host | Fastest, no HTTP listener, but needs a TypeScript host sidecar and changes the process model. Revisit if a TS frontend is ever built. |
| `opencode run` CLI subprocess | Rejected. No incremental streaming, no session reuse, no clean cancellation. |

---

## Capability mapping

| Requested capability | OpenCode mechanism | Slop's job |
|---|---|---|
| Companion: conversation, memory, context, reminders | Persistent sessions; `AGENTS.md`, skills, references, `/api/session/{id}/instructions/entries`; `/api/experimental/automation` with `at`/`every`/`cron`/`event` triggers | Render text, set the agent to a persona, show reminders as messages |
| Knowledge assistant: notes, documents, search, summaries | Built-in read/glob/grep/edit/write; `/api/fs/find`, `/api/fs/list`, `/api/fs/read/*` | Display results; no file code in Slop |
| Research assistant: web, browser, sources | `POST /api/websearch`, `webfetch` tool, Playwright MCP server | Render citations as text; no search client in Slop |
| PC operator: apps, files, Windows, commands | `/api/shell`, PTY routes, session shell; Windows automation via MCP | Show approval requests; no executor in Slop |
| Workflow assistant: multi-step tasks | Commands, skills, subagents, plan mode, TodoWrite, automations | Surface progress through the existing signals |

---

## Event-to-signal translation

OpenCode already emits the events the visual language needs. Map them onto the
**existing** four colours and four shapes only.

| OpenCode event | Slop effect |
|---|---|
| `session.step.first-token` / `session.text.delta` | stream text; triangle; amber stall rule unchanged |
| `session.tool.called` / `session.tool.success` / `session.tool.failed` | existing streaming/thinking/success/error states only — no new visual states |
| `session.execution.succeeded` | success overlay (square, 1.5 s); finalize |
| `session.execution.failed` | error overlay (rect, 2.0 s); finalize |
| `session.execution.interrupted` | `[cancelled]` label, stable idle state; finalize |
| `session.idle` | `__DONE__`, finalize |
| `permission.asked` / `permission.replied` | in-chat approval card with Allow once / Reject; no new signal state |

OpenCode v2.3.2 does not emit `session.idle` after a rejected permission. The
bridge therefore treats all four execution-terminal events as final too: it
queues the signal first, then `__DONE__`, and stops reading that SSE stream.
Without this, a rejected approval leaves the thread job blocked until request
timeout and Send stays disabled. Late tokens from a finalized generation are
ignored by the dispatcher guard. Dump the raw event stream against the installed
version before changing terminal-event handling; docs and dev source have already
disagreed with v2.3.2's live behavior.

Adding a new shape, colour, or motion for tool activity is explicitly out of scope
for this slice.

---

## Request lifecycle (sub-project A)

A bridge is another streaming client, so it inherits the same failure modes as the
current llama.cpp path. Lifecycle correctness is therefore the precondition, not a
detour.

`src/Slop.Lifecycle.ps1` is a pure module — no WPF, no backend — owning:

- phases: `idle → initiated → connected → streaming → completed → finalized`, with
  `failed` reachable from any active phase and `cancelled` as a reason, not a phase;
- separate TTFT, inter-token gap, and since-last-token timestamps;
- a generation guard checked at both enqueue and dequeue boundaries, so a late event
  from a cancelled request cannot overwrite a new request's state;
- SSE parsing with malformed-event counting;
- unconditional disposal of reader, stream, response and client in `finally`;
- distinct labels for cancel, timeout, HTTP error, malformed stream, empty response,
  and partial text followed by interruption.

Timeout is `SLOP_REQUEST_TIMEOUT_SECONDS` (default 300), so the bridge can later use a
longer window without a code change.

Visual behaviour is unchanged: more than 3 seconds since request start still shows
the amber rectangle, regardless of whether the first token has arrived.

Status: Tasks 1–5 complete and verified. The cancellation token reaches the SSE
reader via `ReadLineAsync(token)`, so a stalled backend cannot hold the UI, and Stop
drives finalization immediately rather than waiting for the worker. Live probes
confirm tokens freeze, controls reset, and the next request starts cleanly.

---

## Permissions and safety

Sloppy is OpenCode with a different face. It inherits the global permission model
in `~/.config/opencode/opencode.jsonc`: reads are allowed, edits and shell commands
resolve to `ask`, and web search/fetch are allowed. Slop does not implement a
second permission engine.

`.opencode/opencode.jsonc` defines one primary agent, `sloppy`, which contributes
only its persona and two narrow safety rules:

- **Persona** — `system` loads `~/.config/opencode/personality.md` and adds a
  companion overlay: warm, funny, concise, expert on demand, real-time research.
- **No external workspace grant** — the bundled agent config adds no
  `external_directory` allow. The local service owns workspace scope, and the
  config tripwire rejects any broad grant that gets reintroduced.
- **Fetch hardening** — nine `webfetch` denies covering loopback (`127.0.0.1`,
  any `127.*`, `localhost`, `[::1]`, `0.0.0.0`), cloud metadata
  (`169.254.169.254`, `metadata.google.internal`, `100.100.100.200`), and
  `file://`. These close bypasses that a plain `webfetch: * → allow` leaves open
  in a headless client, where no approval card fires for an allowed fetch.
- **Credential reads** — `service.json`, `~/.ssh/*`, `.env`/`.env.*`,
  `~/.aws/*` and `~/.config/gcloud/*` are denied; `.env.example` stays readable.

The same nine fetch denies and credential-read denies are mirrored in the global
config, so main OpenCode is hardened too. A backup of the global config is kept
alongside it before each edit.

A headless `opencode serve` has no TUI, so a dangling `ask` would hang until the
request timeout. The bridge subscribes to `permission.asked`, renders the card,
and replies with `once` or `reject` only — never `always`, which would persist an
approval. Collapse, Stop, generation change, or window close rejects all pending
requests. The tripwire validates the config before accepting a prompt and fails
closed on a missing password, a missing/invalid `sloppy` agent, a restored
blanket deny, re-enabled repo-wide policies, or a changed approvable set.

`startslop` syncs the repo config into the service's `OPENCODE_CONFIG_CONTENT`
whenever it changes, so a background-service restart cannot silently drop the
agent. The first sync after a config edit restarts the shared service.

OpenCode also appends the project's saved "always" grants after agent rules.
Those are shared with main OpenCode, so an action with an existing saved grant
(such as `shell|Get-Date *` or `edit|*`) runs without a card. This is inherited
main-OpenCode behavior, not a Slop bypass: the bridge only ever replies `once`
or `reject`, so Sloppy itself never creates a saved grant. An action with no
saved grant still resolves to `ask` and renders the card.

The stronger top-level `policies` layer from the original design was removed from
the active config and is not shipped in this checkout; a guarded test still validates
a `.opencode/opencode.jsonc.muted` fixture if one is present. It was inactive in
practice: OpenCode applied those denies to *every* agent in the repo, including the
development session, and a `deny` policy has no approval path. Tool permissions are
defence in depth; the loopback bind and Basic-auth password remain the primary barrier
because several HTTP routes (shell, fs, credential) bypass the agent tool layer.

---

## Visual signals

The observed event inventory, priority rules, and state-to-signal table are
documented in the [event-to-signal translation](#event-to-signal-translation) section.
The frame stroke and rim highlight both follow the effective signal color, and the
rim highlight carries a state-tinted 0x55 alpha. The priority controller is
implemented: stalled resolves to amber, approval is a sticky priority-0 event
held until a decision, and success/error are timed events. Cyan/teal active
tokens and acknowledgement cards remain future work.

Other current visual behavior:

- the compact pea has no literal face: its ~12 drifting pixels are decorative
  "alive" dots, not eyes/nose/mouth. Chat bubbles and System Sense alerts may use
  emoji;
- the ~12 decorative pixels are confined to a rounded 48x48 region around the
  compact pea or clipped to the membrane path when expanded, and follow the
  golden-angle `spiral` pattern while thinking or awaiting approval;
- the expanded chat surface is a 48-point coupled-spring membrane
  (`src/Slop.Frame.ps1`) with an 18 px goo margin. Every point is hard-clamped
  inside the window and outward bulge is tanh-saturated, so the outline can never
  be sliced by the window edge. The inner content Grid receives no transform, and
  its rounded clip is rebuilt in `SizeChanged` so maximize never truncates chat;
- compact size is 484x330. First expansion is 760x540; manual resizes are
  remembered and restored. Three faint, right-aligned controls sit in a rounded
  glass tile, brighten on hover, and expose descriptive automation names. The
  chat and message composer have separate translucent, rimmed surfaces;
- idle is never inert: a 1–3 s gap rolls among nine actions (hop, sit, stretch,
  wander, blink, tilt, bounce, peek, yawn), with breathing/sway continuing in
  every phase. The face rearranges into scattered / ring / cluster / line patterns;
- reduced motion sets the membrane's motion scale to zero: expand/collapse and
  content fade still work, but waves, kicks, pokes and drag slosh are suppressed.

System Sense (`src/Slop.Sense.ps1`) is opt-in, off by default, and persisted in
`%APPDATA%\Slop\settings.json`. A tray toggle enables it; one cached evaluation
runs per minute on the existing 33 ms UI timer. It performs read-only local .NET
reads (CPU, RAM, disk, TCP listeners/connections, process count, best-effort
4625 events), emits at most one thought bubble per scan with a 5-minute
per-alert cooldown, and never takes action, spawns jobs, or contacts the network.
Thought bubbles are reserved for these alerts — no canned facts, jokes or tips.

### Pane views, capability deck and confirmed exit

The WPF shell owns three views: the compact pea, `Extended` chat (the pet stays
visible at the exact click point), and `Full` chat — a large preset inset from the work area,
not a work-area-filling fullscreen. Both chat panes drag by a
transparent top grip; `src/Slop.PaneMovement.ps1` clamps only the pane and stores
and restores the pet rect, so entering Full hides the pea and leaving restores
it exactly.

The control deck (`src/Slop.ControlDeck.ps1`) has six sections — Overview,
Settings, Data, Tools & Skills, Under the hood, Exit. Its six capability toggles
map onto the existing deny-first OpenCode profile in `src/Slop.CapabilityToggles.ps1`
and `src/Slop.OpenCodeProfile.ps1`; all are off by default. Conversation bubbles
are read-only `TextBox` elements: selectable only with the caret, never editable,
with no Copy, clipboard, or read-aloud affordance.

`src/Slop.Shutdown.ps1` normalizes `Sloppy, shutdown` (case, punctuation and
optional comma tolerant), asks `Are you sure? Say or type yes.`, and accepts
`yes`, `y` or `confirm`. Chat text, voice text, the deck Exit button and the tray
Exit menu all pass through that one resolver. Confirmation follows the existing
`Add_Closed` teardown — stop timers, cancel the stream, reject pending approvals,
delete the OpenCode session, close chat — then calls
`[System.Windows.Application]::Current.Shutdown()`. No `Stop-Process` remains.

---

## What we deliberately do not build

- A tool registry in Slop.
- A permission engine in Slop.
- A conversation or memory database in Slop (OpenCode sessions own it).
- A web-search client, browser driver, or Windows automation layer in Slop.
- A workflow engine in Slop.
- A custom model router — provider and model selection are per-session OpenCode config.

---

## Roadmap

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Request lifecycle module + wiring | done |
| 1 | OpenCode HTTP bridge: session, prompt, event translation, interrupt | done |
| 2 | `sloppy` primary agent; inherited permissions + workspace scope | done; live probes passed |
| 3 | MCP servers for browser and Windows automation | planned |
| 4 | Multi-step workflows, reminders, settings control panel | planned |
| Character restyle: spring-membrane body as chat surface | `src/Slop.Frame.ps1`, WPF `Path`/`Clip` | done; live verifier green incl. maximize |
| Companion life, System Sense, expanded screen | `src/Slop.Motion.ps1`, `Slop.Face.ps1`, `Slop.Sense.ps1` | done; 9 headless suites + live verifier green |

Each phase produces testable software on its own. No subagents — local execution only.

"Done" here means: headless `tests/*-check.ps1` green, `verify.ps1` green, and where
UI behavior changed, `tools/verify-motion.ps1` green against a live app with clean
process teardown. Local commits only — no push, PR, deploy or CI edits. The next
session should start from Phase 3, not from an audit of already-verified phases.

---

## Open questions

- Is a cloud provider acceptable for complex reasoning, or must v1 stay fully local?
  (Unresolved. Provider/model remain per-session OpenCode config; local is default.)
- Should reminders use the experimental automations API, or a simpler local timer?
  (Unresolved; belongs to Phase 4.)
- Should approval requests surface in the pea, or stay in the OpenCode TUI for v1?
  (**Resolved:** in-chat approval card, `Allow once` / `Reject` only.)
- Does the companion persona need its own memory store, or are session history plus
  `AGENTS.md`/skills sufficient? (**Resolved for this slice:** no Slop-owned store;
  OpenCode sessions own context and the companion persona is a system prompt.)
- Should the shell stay WPF/PowerShell, or move to a TypeScript frontend?
  (Open. Revisit only if a different frontend is built; it is not a prerequisite for
  any capability.)
