<p align="center">
  <img src="assets/Sloppy.gif" alt="Sloppy demo — animated desktop companion reacting to agent state" width="400">
</p>



# Sloppy

[![CI](https://github.com/shahriarhaqueabir/Sloppy/actions/workflows/ci.yml/badge.svg)](https://github.com/shahriarhaqueabir/Sloppy/actions/workflows/ci.yml)

**A tiny desktop companion that makes your local coding agent visible — and easier to trust.**

Sloppy sits on your desktop as an animated pea. It changes colour, shape and motion with what your agent is actually doing: thinking, working, waiting on a tool, stalled, asking permission, or finishing a reply. When OpenCode asks for approval, the decision appears in the chat as **Allow / Allow once / Reject** instead of hiding in a log.

It is local-first and quiet. There is no cloud account and no telemetry. Sloppy's Tier 1 path runs **Qwen3.5-2B Q4_K_M** on `llama.cpp` b12676 with the GGUF and runtime tracked via Git LFS; the model is 1.3 GB, under GitHub's 2 GB per-file limit. You can also connect your own [OpenCode](https://opencode.ai/) provider; Sloppy is the face and the permission surface, talking to a local service over loopback HTTP.

## Why you might want it

- **See the state, don't guess it.** One resolved signal drives colour, shape, particles and pulse, so the companion cannot disagree with the agent it represents.
- **Approvals where you are.** Permission requests become in-chat cards with generation guards, so a late click cannot approve a newer turn.
- **Stop means stop.** Cancellation reaches the streaming reader itself, not just the initial request.
- **Small and inspectable.** A WPF / PowerShell frontend with headless tests, a live UI verifier and an 18-step source CodeTour.

## Architecture (compact)

`mermaid
flowchart LR
  User[You] --> UI[Sloppy WPF companion]
  UI --> Route[Route planner]
  Route -->|Tier 1 local| Llama[llama.cpp + Qwen GGUF]
  Route -->|Tier 2 agentic| OC[OpenCode + tools/permissions]
  UI --> State[Streaming/thinking/success/error states]
`

## How it works

```text
You --> Sloppy UI --> OpenCode service (loopback HTTP)
                          |
                          | SSE events
                          v
                    signal resolver --> face, colour, motion
                          |
                          v
                    approval card --> your decision --> OpenCode
```

1. **You talk to Sloppy.** The UI forwards your message to a local OpenCode service over loopback HTTP. Nothing leaves your machine unless your OpenCode provider is configured to send it.
2. **OpenCode does the work.** Sessions, tools, providers and permissions all belong to OpenCode. Sloppy does not build a second agent or a second permission engine.
3. **Events become one signal.** Incoming events are stored with an identity, priority and lifetime. The resolver combines them with the base state, using priority and recency to pick a single effective signal - lower priority wins, newest breaks ties.
4. **The signal becomes movement.** Only that resolved signal drives the companion's colour, shape, face, particles and pulse. The pea cannot disagree with the agent it represents.
5. **Decisions stay in the chat.** When OpenCode asks for permission, the request becomes an Allow / Allow once / Reject card. Each decision carries a generation number, so a late click on an old card cannot approve a newer turn.
6. **Stop reaches the stream.** Cancellation is passed to the streaming reader itself, not just the initial request, so tokens stop when you press Stop.

Everything above is wired in the WPF / PowerShell frontend; the capability and the safety policy live in OpenCode config.

## Fun things you can do

- Watch the pea react to your agent in real time — thinking, working, stalled, asking permission, finishing
- Teach it to play digital hide-and-seek: it follows your cursor, hides, peeks
- Turn on System Sense and it leaves thought bubbles when your CPU, RAM, or disk misbehaves

## 🧰 Stack

| Layer | Technology | Notes |
|---|---|---|
| UI | PowerShell 7 + WPF/XAML | Native Windows companion |
| Tier 1 | llama.cpp + Qwen3.5-2B Q4_K_M GGUF | Local/default path (LFS-tracked GGUF) |
| Tier 2 | OpenCode service/SSE | Agentic tools, permissions, audit |
| Tests | Pester 6 | Headless contracts + shell checks |

## 🚀 Provisioning

`powershell
# Prereqs: Windows, PowerShell 7+, OpenCode service configured
# Large runtime/models are Git LFS-tracked: git lfs pull
`

## Quick start

**Windows (nothing installed):** download `install.cmd` from the repo (or the latest release) and double-click it. It shows one folder picker and installs everything inside that folder.

**PowerShell 7.6+ already installed:**

```powershell
$installer = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1
& ([scriptblock]::Create($installer))
```

To choose the folder without the picker and opt into a desktop shortcut:

```powershell
$installer = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1
& ([scriptblock]::Create($installer)) -InstallDir 'D:\Sloppy' -DesktopShortcut
```

Setup asks for one folder and puts the app, bundled runtimes, downloaded models, voice artifacts, and Sloppy's `data\` folder inside it. The desktop shortcut is optional and off by default; the Start Menu shortcut is always created. Both launch without a PowerShell console window.

Sloppy needs PowerShell 7.6 or newer. The installer installs it if missing.

**Upgrading:** re-running setup upgrades in place and preserves `data\config.json` and `data\persona.md`. Settings from an older `%LOCALAPPDATA%\Sloppy` install do not move automatically; start fresh in the chosen folder.

**From a clone (headless, no console window):**

Double-click `run.cmd`. It uses a VBScript wrapper so no PowerShell console
flashes. `pwsh -WindowStyle Hidden -STA -File src/Slop.ps1` still works but can
briefly show a console on Windows.

Requirements:

- Windows
- PowerShell 7.6 or later, in STA mode
- Git LFS (only for a source checkout; the installer downloads the large models itself)
- For Tier 1: `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` is downloaded and checksum-verified during setup
- Tier 1 runs on any Windows PC: an NVIDIA/CUDA build is used when available, otherwise a bundled CPU build. No GPU required.
- For voice: the Whisper CLI and DLLs are bundled; `ggml-small.bin` is downloaded and checksum-verified during setup
- Optional: a local OpenCode service with your agent, model and provider configured for Tier 2/OpenCode routing

Sloppy prefers whatever OpenCode config you already have. If there is none, it installs a minimal zero-trust config; it never overwrites an active one. Tier 1 uses the local Qwen3.5-2B brain under `runtime/models/`, and opt-in push-to-talk audio is transcribed locally by the bundled Whisper small setup before being sent through the same text path. Nothing is uploaded for Tier 1. Image capture and `mmproj` remain unused readiness hooks; there are no spoken replies.

## 📋 Playbook (short)

1. **Scope**: small always-on companion, local-first, honest states.
2. **Shell**: WPF overlay + tray + clear visual state model.
3. **Brains**: Tier 1 local default, Tier 2 OpenCode opt-in upgrade.
4. **Safety**: permissioned agent actions, no credential leakage, no fake live claims.
5. **Verify**: Pester contracts, tour anchors, live smoke before claiming UI behavior.

## What it is not

Sloppy is a desktop frontend, not a model, a standalone chatbot, or a hosted service. Sessions, tools, providers and permissions belong to OpenCode. That boundary is deliberate: one broker owns capability, so the UI never has to guess what a model is allowed to do.

The companion product is still early. [Product direction](docs/product-direction.md) records the candidate modes; shipped behavior is documented in [architecture](docs/architecture.md) and the [technical showcase](docs/SHOWCASE.md).

## Proof

```powershell
# Full Pester aggregate
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 6.0; Invoke-Pester -Path 'tests/Slop.Tests.ps1' -CI -Output Detailed"

# Geometry verifier — 18 scenarios
pwsh -NoProfile -File tools/verify-geometry.ps1

# Live UI verifier: expand, maximize, send, stream, drag, collapse
pwsh -NoProfile -File tools/verify-motion.ps1
```

The tour guard checks all source anchors, so the architecture walkthrough cannot silently drift away from the code.

## Read more

- [Architecture](docs/architecture.md)
- [Technical showcase](docs/SHOWCASE.md)
- [18-step architecture CodeTour](.tours/architect-slop-architecture.tour)
- [OpenCode route security review](docs/security/opencode-route-review.md)

## License

MIT — see [LICENSE](LICENSE). The desktop icon is included as `assets/sloppy.ico`.
