# Single-Folder Installer — Design Spec

**Date:** 2026-11-26  
**Status:** Approved design; implementation plan pending  
**Scope:** Public Sloppy repo (`<repo-root>`) — installer, launchers, path helpers, CI release artifacts  
**Working tree constraint:** `main` is clean and pushed; `origin/main...HEAD` is `0/0`. Do not force-push, deploy, or change remote visibility. Preserve all existing LFS assets and user data.

## Context

Today Sloppy's install is split across several implicit locations:

- `install.ps1` clones/updates `%LOCALAPPDATA%\Sloppy`.
- App code and `runtime\` live in that clone.
- `config.json` and `persona.md` live in `%LOCALAPPDATA%\Sloppy` through `Get-SlopUserDataPath`.
- `Get-SlopRuntimePaths` defaults to `%LOCALAPPDATA%\Programs\Sloppy`.
- `Get-SlopVoiceInstallRoot` historically defaulted to `Programs\Sloppy`; it now accepts the real app root from `Slop.ps1`, but still has a hard-coded fallback.
- The Start Menu shortcut lives under `%APPDATA%` and now points at `wscript.exe` + `run.vbs`.

This produced a real end-user failure: the bundled brain reported a missing `llama-server.exe` because the route planner had the correct app root but never passed it to the runtime path helper. Similar path drift would keep breaking voice and data on a fresh install.

The user asked for one user-chosen folder that holds the app, runtimes, models, and its own data, with both the double-click installer and the one-liner using the same behavior. They specifically asked for an optional desktop shortcut checkbox and suggested Inno Setup. They also chose a hybrid payload, pinned release assets with local cache reuse, and no user-facing "testability" concept.

## Goal

Make a fresh Windows install a single guided operation:

- Ask where to create the app folder.
- Install app code, bundled binaries, models, and Sloppy's own data under that folder.
- Offer an unchecked "Create desktop shortcut" checkbox; always create the Start Menu entry.
- Give the PowerShell one-liner the same installer, with optional `-InstallDir` and `-DesktopShortcut` parameters.
- Keep launch headless through `wscript.exe` + `run.vbs`.
- Preserve user data when a later installer run upgrades the app in place.
- Keep all path resolution derived from one canonical app root.

## Non-Goals

- No user-visible test or debug mode. CI isolation stays a hidden environment override.
- No under-the-hood AI activity view in this change stream; it is deferred.
- No Tier 3 custom provider work.
- No bundling of OpenCode. Tier 2 remains a separate service Sloppy talks to.
- No automatic migration of config/persona from old `%LOCALAPPDATA%\Sloppy` locations.
- No desktop shortcut unless the user selects it.
- No force-push, deploy, visibility change, or subagent use.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Installer framework | Inno Setup 6.5.2+ | Native folder page, native optional task checkbox, `/DIR=` CLI support, and the 2 GB single-EXE limit was removed in 6.5.2. |
| Single source of paths | One `Get-SlopAppRoot` | Removes the class of bug where each helper invents its own default. Test override remains internal. |
| Data location | `{app}\data\config.json` and `{app}\data\persona.md` | User chose app + runtimes + own data in one folder. |
| Payload | Hybrid | EXE bundles code/launchers/small runtime binaries; two large models download during install. |
| Model source | Pinned release assets + cache reuse | Version-locked downloads, checksum verified; reuse only a previous marked install, no broad disk scan. |
| Desktop shortcut | `[Tasks]` entry, unchecked by default | Matches the user's explicit checkbox request. |
| Re-runs | Detect previous `{app}` from Inno Setup AppId, upgrade in place | User chose update-in-place; no migration from old locations. |
| Upgrade safety | `data\` excluded from uninstall | Config and persona must survive reinstall. |
| CLI entry | `install.ps1` downloads/runs the same EXE | One behavior for GUI and CLI. |

## Design

### 1. Installed layout

`{app}` is the folder chosen in the wizard or supplied with `-InstallDir`.

```
{app}\
  src\
  run.cmd
  run.vbs
  assets\
  tools\
  runtime\llama-b12676-bin-win-cpu-x64\
  runtime\llama-b12676-bin-win-cuda-13.5-x64\
  runtime\whisper\          # CLI + DLLs bundled; model downloaded
  runtime\models\           # Qwen GGUF downloaded
  data\
    config.json
    persona.md
  .sloppy-install.json      # version + root marker
```

Only two things remain outside `{app}`:

1. The Start Menu shortcut, and the desktop shortcut only when selected.
2. The OpenCode service configuration, because OpenCode is an external Tier 2 service.

`installer/Sloppy.iss` owns `[Setup]`, `[Files]`, `[Icons]`, `[Tasks]`, and a `[Code]` post-install step. Inno Setup's AppId registry entry supplies the previous install directory on re-runs; no additional discovery marker is introduced.

### 2. Installer UX

`install.cmd` remains the double-click entry point. It downloads and starts `SloppySetup.exe`.

The one-liner remains `irm .../install.ps1 | iex`. `install.ps1` becomes a thin wrapper that:

- downloads the pinned `SloppySetup.exe`;
- runs it with the wizard when no `-InstallDir` is supplied;
- maps `-InstallDir 'D:\Sloppy'` to `/DIR="D:\Sloppy"`;
- maps `-DesktopShortcut` to `/TASKS=desktopicon`;
- uses silent flags only when `-InstallDir` is supplied, so the picker is not left hanging in automation.

Because `Invoke-Expression` cannot bind named parameters cleanly, docs show the parameter form as:

```powershell
$installer = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1
& ([scriptblock]::Create($installer)) -InstallDir 'D:\Sloppy' -DesktopShortcut
```

Inno Setup provides the rest:

```ini
[Setup]
DefaultDirName={autopf}\Sloppy
PrivilegesRequired=lowest

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Icons]
Name: "{group}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"
Name: "{autodesktop}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon
```

### 3. Hybrid payload and model download

Bundled in the EXE:

- `src\`, `tools\`, `assets\`, `run.cmd`, `run.vbs`, `README.md`, `LICENSE`, third-party notices;
- `runtime\llama-b12676-bin-win-cpu-x64\` and `runtime\llama-b12676-bin-win-cuda-13.5-x64\`;
- `runtime\whisper\` CLI and DLLs.

Downloaded in `CurStepChanged(ssPostInstall)`:

| Asset | Destination | Integrity |
|---|---|---|
| `Qwen3.5-2B-Q4_K_M.gguf` | `{app}\runtime\models\` | SHA-256 from release `SHA256SUMS.txt` |
| `ggml-small.bin` | `{app}\runtime\whisper\models\` | SHA-256 from release `SHA256SUMS.txt`; existing pinned SHA-1 remains documented |

Download URLs are compile-time constants tied to one release tag. The post-install helper invokes `pwsh` with `Invoke-WebRequest -OutFile` and `Get-FileHash`; the installer checks the PowerShell prerequisite before running it. Download failure writes a clear message naming the asset and URL, leaves a retryable state, and does not silently leave a zero-byte file.

Cache reuse is narrow: if Inno Setup's AppId registry entry points to a previous install with a same-version `.sloppy-install.json`, and the existing model file matches the expected hash, copy it into the new `{app}` instead of downloading. No scanning of arbitrary drives or folders.

### 4. Canonical path contract

Introduce `Get-SlopAppRoot` as the only app-root source. It resolves to the parent of `src\` at runtime and honors `SLOP_TEST_INSTALL_ROOT` only for CI/headless isolation.

Derive every other path from it:

| Current helper | New source |
|---|---|
| `Get-SlopUserDataPath` | `Join-Path (Get-SlopAppRoot) 'data'` |
| `Get-SlopConfigPath` | `Join-Path (Get-SlopUserDataPath) 'config.json'` |
| `Get-SlopPersonaPath` | `Join-Path (Get-SlopUserDataPath) 'persona.md'` |
| `Get-SlopRuntimePaths -InstallRoot` | `Get-SlopAppRoot` when no explicit root is passed |
| `Get-SlopVoiceInstallRoot` | `Get-SlopAppRoot` when no explicit root is passed |
| `tools/slop-preflight.ps1` | receives the app root explicitly from the shell |

Remove `%LOCALAPPDATA%\Sloppy` and `%LOCALAPPDATA%\Programs\Sloppy` from production path fallbacks in `Slop.Config.ps1`, `Slop.LocalModel.ps1`, `Slop.Audio.ps1`, `Slop.Disclosure.ps1`, `Slop.Surfaces.ps1`, and the data-location line in `Slop.ps1`. Test files and live verifiers may keep their explicit isolated overrides.

`SLOP_TEST_APPDATA` is retired in favor of `SLOP_TEST_INSTALL_ROOT`; existing verifier scripts are updated in the same change.

### 5. Upgrade and data preservation

- Re-running the installer defaults its folder page to the previous Inno Setup AppId install location.
- `[Dirs] {app}\data` and any existing files under it are marked so uninstall does not remove them.
- `.sloppy-install.json` records the version and root. A mismatched version is treated as a new install for cache purposes but never causes data deletion.
- The new installer replaces code/runtime files in place. It does not copy old `config.json` or `persona.md` from `%LOCALAPPDATA%\Sloppy`.

### 6. CI and release pipeline

A Windows CI job:

1. Checks out with LFS and runs `git lfs pull`.
2. Installs Inno Setup 6.5.2+ via a pinned, reviewed action or package source.
3. Compiles `installer/Sloppy.iss` with the release version/tag supplied from the tag.
4. Uploads `SloppySetup.exe`, the two large model assets, and `SHA256SUMS.txt` to the same release.
5. Runs a silent-install smoke test into a temp directory using a test override for model fixtures, then verifies the expected layout and shortcut targets.

Downgrade to Inno Setup disk spanning only if EXE startup becomes unacceptable; the current payload is within the single-EXE limit.

### 7. Acceptance criteria

- A fresh machine sees one folder picker and an unchecked desktop shortcut checkbox.
- Selecting the desktop checkbox creates both Start Menu and desktop shortcuts; leaving it unchecked creates only Start Menu.
- Both shortcuts launch `wscript.exe` with `run.vbs`; no PowerShell console flashes.
- All runtime, CLI, DLL and downloaded model files exist under the chosen folder and pass checksums.
- The one-liner with `-InstallDir` and `-DesktopShortcut` produces the same layout without a picker.
- Re-running the installer upgrades in place and preserves `data\config.json` and `data\persona.md`.
- `Get-SlopRuntimePaths`, `Get-SlopVoiceInstallRoot`, `Get-SlopUserDataPath`, preflight and disclosure copy all agree on the app root.
- Full Pester gate, CI, and CodeQL are green.

## Risks and trade-offs

- The hybrid installer still needs network for the two models; retry and checksum handling are required, and failure must be explicit.
- Release assets roughly double in total size because models are published both as repo LFS objects and release assets.
- Inno Setup upgrade behavior must preserve `data\`; this needs a smoke test, not just a static assertion.
- Moving data out of `%LOCALAPPDATA%\Sloppy` means existing users' settings do not automatically follow. This is accepted under the no-migration decision and must be stated in release notes.
- PowerShell 7.6 remains a runtime prerequisite; the installer must check/bootstrap it before the post-install download helper runs.

## Verification plan

- Add `tests/slop-installer-check.ps1` for `.iss` structure, optional desktop task, headless shortcut target, `/DIR` mapping, and absence of hard-coded production roots.
- Extend config, audio, route and shell checks for the single app-root contract.
- Run the canonical CI-equivalent Pester gate locally before commit.
- After push, confirm CI and CodeQL on the pushed SHA.
- Live user verification remains required for console suppression, visible styling, tier switching, and model readiness; this spec does not claim those were verified by the agent.
