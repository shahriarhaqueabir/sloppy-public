# Single-Folder Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute inline in this session only — do not dispatch subagents (explicit user constraint).

**Goal:** Replace Sloppy's split install with one user-chosen folder holding app code, runtimes, models, voice artifacts and Sloppy's own data, delivered through one Inno Setup wizard shared by the GUI double-click and the PowerShell one-liner.

**Architecture:** Inno Setup compiles a single-EXE installer containing code and small binaries, then runs a headless `pwsh` post-install helper that downloads and checksum-verifies the two large models. All runtime path helpers derive from one `Get-SlopAppRoot`, with a hidden `SLOP_TEST_INSTALL_ROOT` override for CI only. Tier is derived from `brain`: Tier 1 is built-in local Qwen, Tier 2 is OpenCode, and Tier 3 is reserved/undecided. The existing `custom` brain is not Tier 3; it resolves to `0`, meaning "no released tier." The free/paid field and `opencode-paid` route kind are removed rather than relabelled.

**Tech Stack:** Windows PowerShell 7.6+, Pester 6, Inno Setup 6.5.4 (Chocolatey `InnoSetup` pin), WPF/VBScript headless launcher, GitHub Actions, Git LFS release assets.

**Source of truth:** `docs/decisions/2026-11-26-single-folder-installer.md` (approved). Where this plan adds detail, it stays inside that spec's decisions.

**Constraints carried into every task:**
- No subagents, no force-push, no deploy, no tag, no release, no visibility change, and no remote change without explicit user approval.
- Preserve existing LFS assets and user data. Do not bundle `gemma-4-E2B_q4_0-it.gguf` or `gemma-4-E2B-it-mmproj.gguf`.
- No migration from old `%LOCALAPPDATA%` locations; old settings deliberately do not follow.
- No user-facing test/debug mode. `SLOP_TEST_INSTALL_ROOT` and `SLOP_TEST_ASSET_FIXTURES` are hidden CI/internal overrides only.
- Commit only explicit paths. Never `git add -A`. Local commits only until the user approves a push.
- `docs/superpowers/` is gitignored; this plan lives in tracked `docs/plans/`.

**Git state is a snapshot:** do not infer current divergence from the spec or plan. Verify with `git status` and `git rev-list --left-right --count origin/main...HEAD` before any future push.

---

## File structure

| File | Responsibility |
|---|---|
| `src/Slop.Config.ps1` | Canonical `Get-SlopAppRoot`, data paths, config v3 schema, tier/model catalogs |
| `src/Slop.LocalModel.ps1` | Runtime paths derived from `Get-SlopAppRoot` |
| `src/Slop.Audio.ps1` | Voice install root derived from `Get-SlopAppRoot` |
| `src/Slop.Route.ps1` | Route taxonomy without `opencode-paid` |
| `src/Slop.Onboarding.ps1` | Tier-based wizard; no paid-provider checkbox |
| `src/Slop.ps1` | Tier labels, shared model options, corrected data-location copy, autostart target |
| `src/Slop.Disclosure.ps1`, `src/Slop.Surfaces.ps1` | Copy and surface contracts without stale paths/controls |
| `tools/slop-assets.json` | Pinned release URLs, destinations, SHA-256 expectations |
| `tools/slop-fetch-assets.ps1` | Headless download/cache/verify helper |
| `tools/slop-preflight.ps1` | Explicit install-root argument |
| `tools/verify-motion.ps1` | Live verifier moved to `SLOP_TEST_INSTALL_ROOT` |
| `installer/Sloppy.iss` | Inno Setup script: `[Setup]`, `[Files]`, `[Dirs]`, `[Tasks]`, `[Icons]`, `[Code]` |
| `install.ps1`, `install.cmd` | Thin wrappers that download/run the same `SloppySetup.exe` |
| `run.cmd`, `run.vbs` | Headless launchers derived from script location |
| `tests/slop-installer-check.ps1` | New static contract suite for installer, manifest, helper, wrappers |
| `.github/workflows/release.yml` | Tag-triggered Inno compile, release assets, silent-install smoke |
| `.tours/architect-slop-architecture.tour`, `tests/slop-tour-check.ps1` | Anchors refreshed after source edits |
| `README.md` | Install command, one-folder layout, no-migration note |

**Task order rationale:** pure helpers first (1–3), UI and copy consumers next (4–5), packaging next (6–9), anchors/docs last (10). Each task produces a testable state.

---

### Task 1: One canonical app root

**Files:**
- Modify: `src/Slop.Config.ps1:1-33`
- Modify: `src/Slop.LocalModel.ps1:1-6,27-30`
- Modify: `src/Slop.Audio.ps1:1-24`
- Test: `tests/slop-config-check.ps1`
- Test: `tests/slop-localmodel-check.ps1`
- Test: `tests/slop-audio-check.ps1`

- [ ] **Step 1: Write failing config tests for the canonical root**

In `tests/slop-config-check.ps1`, replace the `BeforeEach` block at lines 7-12 with:

```powershell
    BeforeEach {
        $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('slop-config-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'data') -Force | Out-Null
        $script:ConfigPath = Join-Path $script:TestRoot 'data\config.json'
        $script:PersonaPath = Join-Path $script:TestRoot 'data\persona.md'
    }
```

The extra `data` directory matters: several later tests write to `$script:ConfigPath` with `[IO.File]::WriteAllText`, which does not create parent directories.

Replace the test at lines 20-31 with:

```powershell
    It 'honours the disposable install-root override without touching LOCALAPPDATA' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:TestRoot
            Get-SlopAppRoot | Should -Be ([IO.Path]::GetFullPath($script:TestRoot))
            Get-SlopUserDataPath | Should -Be (Join-Path $script:TestRoot 'data')
            Get-SlopConfigPath | Should -Be $script:ConfigPath
            Get-SlopPersonaPath | Should -Be $script:PersonaPath
        } finally {
            if ($null -eq $previous) { Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue }
            else { $env:SLOP_TEST_INSTALL_ROOT = $previous }
        }
    }
```

Append inside the `Describe 'Slop.Config'` block:

```powershell
    It 'does not fall back to LOCALAPPDATA in production code' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Config.ps1') -Raw
        $src | Should -Not -Match 'Join-Path \$env:LOCALAPPDATA ''Sloppy'''
        $src | Should -Not -Match 'SLOP_TEST_APPDATA'
    }
```

- [ ] **Step 2: Run the config suite to confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-config-check.ps1 -Output Detailed"`
Expected: FAIL with `The term 'Get-SlopAppRoot' is not recognized` and the LOCALAPPDATA assertion failing.

- [ ] **Step 3: Implement `Get-SlopAppRoot` and derived paths**

Replace `src/Slop.Config.ps1:1-33` with:

```powershell
# Sloppy portable configuration. Pure path/schema/IO helpers; no WPF, no network.
$ErrorActionPreference = 'Stop'

# Captured at dot-source time so the root stays tied to this file even when the
# function is called from the WPF shell or a Pester container.
$script:SlopConfigFileRoot = $PSScriptRoot
$script:SlopConfigVersion = 3
$script:SlopIdentityColors = @{
    ocean = '#6366F1'
    moss  = '#14B8A6'
    plum  = '#A855F7'
    ember = '#EC4899'
    sky   = '#38BDF8'
    stone = '#94A3B8'
}
$script:SlopBrains = @('builtin', 'custom', 'opencode')
$script:SlopPersonalities = @('calm', 'playful', 'curious', 'professional')
$script:SlopCapabilityProfiles = @('companion', 'workspace', 'power')

function Get-SlopAppRoot {
    # Hidden CI/headless isolation only. Never surfaced in the UI or docs as a
    # user feature.
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_INSTALL_ROOT)) {
        return [IO.Path]::GetFullPath($env:SLOP_TEST_INSTALL_ROOT)
    }
    if ($script:SlopConfigFileRoot) {
        return [IO.Path]::GetFullPath((Join-Path $script:SlopConfigFileRoot '..'))
    }
    throw 'Cannot resolve the Sloppy app root'
}

function Get-SlopUserDataPath { return Join-Path (Get-SlopAppRoot) 'data' }
function Get-SlopConfigPath    { return Join-Path (Get-SlopUserDataPath) 'config.json' }
function Get-SlopPersonaPath   { return Join-Path (Get-SlopUserDataPath) 'persona.md' }
function Get-SlopIdentityColors { return @{} + $script:SlopIdentityColors }
function Get-SlopPersonalities  { return @($script:SlopPersonalities) }
function Get-SlopBrains         { return @($script:SlopBrains) }
function Get-SlopCapabilityProfiles { return @($script:SlopCapabilityProfiles) }
function Get-SlopIdentityColor {
    param([Parameter(Mandatory)][string]$ColorKey)
    if (-not $script:SlopIdentityColors.ContainsKey($ColorKey)) { throw "unknown identity color: $ColorKey" }
    return $script:SlopIdentityColors[$ColorKey]
}
```

Note: `$script:SlopConfigVersion = 3` is intentional here; Task 2 supplies the v3 migration and removes `providerTier`. Step 3 hardens the path contract first so a later failure is attributable.

- [ ] **Step 4: Run the config suite to confirm GREEN for paths**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-config-check.ps1 -Output Detailed"`
Expected: the rewritten override test and the new LOCALAPPDATA guard pass, and no existing config test regresses because of the `data\` path change. Any other failure is a pre-existing regression - stop and fix before continuing.

- [ ] **Step 5: Migrate runtime and voice helpers**

In `src/Slop.LocalModel.ps1`, insert after line 2:

```powershell
if (-not (Get-Command Get-SlopAppRoot -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Slop.Config.ps1')
}
```

and change the `Get-SlopRuntimePaths` parameter block at lines 27-32 from:

```powershell
function Get-SlopRuntimePaths {
    param(
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Sloppy'),
        [AllowEmptyString()][string]$ModelFile = 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf',
        [AllowEmptyString()][string]$MmprojFile = ''
    )
}
```

to (only the `$InstallRoot` default changes; the other two lines stay byte-identical):

```powershell
function Get-SlopRuntimePaths {
    param(
        [string]$InstallRoot = (Get-SlopAppRoot),
        [AllowEmptyString()][string]$ModelFile = 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf',
        [AllowEmptyString()][string]$MmprojFile = ''
    )
}
```

In `src/Slop.Audio.ps1`, replace lines 12-23 with:

```powershell
function Get-SlopVoiceInstallRoot {
    param([string]$InstallRoot)
    if (-not (Get-Command Get-SlopAppRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'Slop.Config.ps1')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SLOP_TEST_INSTALL_ROOT)) {
        return [IO.Path]::GetFullPath($env:SLOP_TEST_INSTALL_ROOT)
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        return [IO.Path]::GetFullPath($InstallRoot)
    }
    return Get-SlopAppRoot
}
```

- [ ] **Step 6: Add helper RED tests, then confirm GREEN**

Append to `tests/slop-localmodel-check.ps1`:

```powershell
    It 'defaults runtime paths to the canonical app root' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:TestRoot
            $paths = Get-SlopRuntimePaths
            $paths.InstallRoot | Should -Be ([IO.Path]::GetFullPath($script:TestRoot))
            $paths.ModelFile | Should -Match [regex]::Escape('runtime\models\Qwen3.5-2B-Q4_K_M.gguf')
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }
```

Append to `tests/slop-audio-check.ps1`:

```powershell
    It 'defaults the voice root to the canonical app root' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $script:TestRoot
            Get-SlopVoiceInstallRoot | Should -Be ([IO.Path]::GetFullPath($script:TestRoot))
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }
```

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-localmodel-check.ps1,tests/slop-audio-check.ps1 -Output Detailed"`
Expected: PASS after Step 5; RED before it (missing default / stale fallback).

- [ ] **Step 7: Commit**

```bash
git add src/Slop.Config.ps1 src/Slop.LocalModel.ps1 src/Slop.Audio.ps1 tests/slop-config-check.ps1 tests/slop-localmodel-check.ps1 tests/slop-audio-check.ps1
git commit -m "feat: derive all Sloppy paths from one canonical app root"
```

---

### Task 2: Config v3 — tier without free/paid

**Files:**
- Modify: `src/Slop.Config.ps1:51-94,101-166,168-226,282-343`
- Test: `tests/slop-config-check.ps1`

- [ ] **Step 1: Write failing v3 tests**

Append to `tests/slop-config-check.ps1`. Tier 3 is reserved and undecided; `Resolve-SlopTier -Brain 'custom'` returning `0` means "no released tier," not a hidden Tier 3 assignment.

```powershell
    It 'has no free or paid tier field in the default config' {
        $cfg = New-SlopDefaultConfig
        $cfg.version | Should -Be 3
        $cfg.ContainsKey('providerTier') | Should -BeFalse
        $cfg.brain | Should -Be 'builtin'
        $cfg.model | Should -Be 'big-pickle'
    }

    It 'maps tier 1 and tier 2 to different model option sets' {
        @(Get-SlopBrainModelOptions -Brain 'builtin') | Should -Be @('Qwen3.5-2B Q4_K_M')
        @(Get-SlopBrainModelOptions -Brain 'opencode') | Should -Be @('big-pickle','beam-free')
        @(Get-SlopBrainModelOptions -Brain 'custom') | Should -Be @()
        Resolve-SlopTier -Brain 'builtin' | Should -Be 1
        Resolve-SlopTier -Brain 'opencode' | Should -Be 2
        Resolve-SlopTier -Brain 'custom' | Should -Be 0
    }

    It 'migrates a v2 config with providerTier to v3 without rejecting it' {
        $path = Join-Path $script:TestRoot 'v2-config.json'
        $v2 = New-SlopDefaultConfig
        $v2.version = 2
        $v2.providerTier = 'paid'
        $v2 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8
        $result = Read-SlopConfig -ConfigPath $path
        $result.Ok | Should -BeTrue
        $result.Config.version | Should -Be 3
        $result.Config.ContainsKey('providerTier') | Should -BeFalse
        $result.Config.providerLocality | Should -Be 'remote'
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-config-check.ps1 -Output Detailed"`
Expected: FAIL for `Get-SlopBrainModelOptions`, `Resolve-SlopTier`, default version, and v2 migration.

- [ ] **Step 3: Replace the defaults, catalog, validation and migration**

Replace `src/Slop.Config.ps1:51-94` (`New-SlopDefaultConfig`) with:

```powershell
function New-SlopDefaultConfig {
    return @{
        version           = $script:SlopConfigVersion
        name              = 'Sloppy'
        ownerName         = 'friend'
        color             = 'ocean'
        personality       = 'calm'
        instructions      = 'Be concise, honest, and helpful.'
        brain             = 'builtin'
        endpointUrl       = 'http://127.0.0.1:11434'
        modelName         = 'Qwen3.5-2B Q4_K_M'
        autostart         = $true

        # Tier 1 bundled local brain (Qwen3.5-2B Q4_K_M). Readiness flags stay
        # hooks; Tier 1 voice resolves through Slop.Audio.ps1 paths.
        localModelName    = 'Qwen3.5-2B Q4_K_M'
        localModelFile    = 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf'
        localMmprojFile   = ''
        localContextSize  = 8192
        localVisionReady  = $true
        localAudioReady   = $true

        # Tier 1 voice input, opt-in and local only.
        voiceEnabled      = $false
        whisperRuntimeFile = 'runtime\whisper\whisper-cli.exe'
        whisperModelFile   = 'runtime\whisper\models\ggml-small.bin'
        whisperLanguage    = 'auto'
        voiceMaxSeconds    = 30

        # Tier 2 route fields. Locality is a preference; disclosure is driven by
        # observed endpoint evidence, not by a stored price label.
        provider          = 'opencode'
        providerLocality  = ''
        capabilityProfile = 'companion'
        agentId           = 'sloppy'
        model             = 'big-pickle'
        agent             = @{}
        openCodeBaseUrl   = 'http://127.0.0.1:28894'
        serviceConfigPath = ''
        openCodeSessionId = ''
    }
}

function Get-SlopBrainOrder { return @('builtin', 'opencode', 'custom') }

function Get-SlopBrainModelOptions {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Brain)
    switch ([string]$Brain) {
        'builtin'  { return @('Qwen3.5-2B Q4_K_M') }
        'opencode' { return @('big-pickle', 'beam-free') }
        default    { return @() }
    }
}

function Resolve-SlopTier {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Brain)
    switch ([string]$Brain) {
        'builtin'  { return 1 }
        'opencode' { return 2 }
        default    { return 0 }
    }
}
```

In `Test-SlopConfig`, delete lines 128-130 (the `providerTier` validation block) entirely. Keep `providerLocality` validation unchanged.

In `Read-SlopConfig`, replace the version-normalization lines 183-187 with:

```powershell
    # Version 0/1/2 configs are pre-v3 shapes. Normalize numeric JSON values to
    # [int] before validation because ConvertFrom-Json emits [long].
    if ($cfg.version -is [int] -or $cfg.version -is [long]) { $cfg.version = [int]$cfg.version }
    else { $cfg.version = 3 }
    if ($cfg.version -lt 3) {
        # v2 carried providerTier=free|paid. The $cfg loop above copies only v3
        # default keys, so the legacy value lives on $raw (the parsed JSON) and
        # MUST be read from there. Drop the price label; a paid remote choice
        # still resolves to the same observed remote route.
        $legacyTier = $raw.PSObject.Properties['providerTier']
        if ($null -ne $legacyTier -and [string]$legacyTier.Value -eq 'paid' -and
            [string]::IsNullOrWhiteSpace([string]$cfg.providerLocality)) {
            $cfg.providerLocality = 'remote'
        }
        $cfg.version = 3
    }
```

In `Set-SlopConfigBrain`: remove the `-ProviderTier` parameter line 288, remove `$candidate.providerTier = ...` at line 301, and remove the two `providerTier` assignments in the `builtin`/`custom` switch arms (lines 317 and 325). No other parameter changes.

- [ ] **Step 4: Remove stale `providerTier` from config/provider tests**

Removing the validation block and the `-ProviderTier` parameter breaks existing tests. Apply these exact edits.

In `tests/slop-config-check.ps1`:
- line 98: delete the whole line `@{ key='providerTier'; value='enterprise' }`.
- line 113: delete the whole line `$cfg.providerTier = 'free'`.
- lines 286, 302, 310, 316, 333, 344: delete the `-ProviderTier 'paid'` / `-ProviderTier 'free'` token on each line. Keep every other argument and the trailing backtick.
- line 328: delete the whole line `$configured.providerTier = 'paid'`.
- line 338: delete the whole line `$r.Config.providerTier | Should -Be 'free'`.

In `tests/slop-provider-check.ps1` line 116: delete `providerTier='free'` from the hashtable (keep the surrounding `brain` and `providerLocality` entries on that line).

After the edits, `providerTier` must remain only in the intentional v2-migration test and migration code. `tests/slop-provider-check.ps1` must have no matches, and `tests/slop-config-check.ps1` may match only the v2 migration case and its two `ContainsKey('providerTier')` assertions. A blanket "no matches" check would contradict the required migration test.

```powershell
Select-String -Path tests/slop-provider-check.ps1 -Pattern 'providerTier|ProviderTier'
```

- [ ] **Step 5: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-config-check.ps1,tests/slop-provider-check.ps1 -Output Detailed"`
Expected: all config and provider tests PASS. If a v2 test complains about `version` being `[long]`, the `[int]` normalization above is wrong - fix before continuing.

- [ ] **Step 6: Commit**

```bash
git add src/Slop.Config.ps1 tests/slop-config-check.ps1 tests/slop-provider-check.ps1
git commit -m "feat: remove free/paid tier from config v3 and add tier model catalogs"
```

---

### Task 3: Route taxonomy without `opencode-paid`

**Files:**
- Modify: `src/Slop.Route.ps1:4-21,45-71`
- Test: `tests/slop-route-check.ps1`

- [ ] **Step 1: Write failing route tests**

Replace the test at `tests/slop-route-check.ps1:25-28` with:

```powershell
    It 'classifies an OpenCode route without a paid tier' {
        Resolve-SlopRouteKind -Config @{ brain='opencode'; providerLocality='remote' } |
            Should -Be 'opencode-remote'
        @(Get-SlopRouteCatalog).Keys | Should -Not -Contain 'opencode-paid'
    }
```

Append:

```powershell
    It 'keeps route planning independent of any tier field' {
        $cfg = New-SlopDefaultConfig
        $cfg.brain = 'opencode'
        $cfg.providerLocality = 'remote'
        $cfg.provider = 'opencode-go'
        $cfg.agentId = 'sloppy'
        $cfg.openCodeBaseUrl = 'http://127.0.0.1:28894'
        $cat = Get-SlopRouteCatalog
        $cat['opencode-remote'].TermsRequired | Should -BeTrue
        $cat['opencode-remote'].Locality | Should -Be 'Remote'
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-route-check.ps1 -Output Detailed"`
Expected: FAIL — `Resolve-SlopRouteKind` still returns `opencode-paid` and the catalog still contains that key.

- [ ] **Step 3: Remove the paid route kind**

Replace `src/Slop.Route.ps1:4-21` with:

```powershell
function Get-SlopRouteCatalog {
    return @{
        'local-bundled'   = @{ Harness='bundled';  Locality='Local';  TermsRequired=$false }
        'custom'          = @{ Harness='Custom';   Locality='Local';  TermsRequired=$false }
        'opencode-local'  = @{ Harness='OpenCode'; Locality='Local';  TermsRequired=$false }
        'opencode-remote' = @{ Harness='OpenCode'; Locality='Remote'; TermsRequired=$true  }
    }
}

function Resolve-SlopRouteKind {
    param([Parameter(Mandatory)][hashtable]$Config)
    if ([string]$Config.brain -eq 'custom') { return 'custom' }
    if ([string]$Config.brain -ne 'opencode') { return 'local-bundled' }
    if ([string]$Config.providerLocality -eq 'local') { return 'opencode-local' }
    return 'opencode-remote'
}
```

In `Get-SlopRoutePlan`, replace lines 68-70 with:

```powershell
        if ($observedLocal) { $kind = 'opencode-local' }
        else { $kind = 'opencode-remote' }
```

The catalog no longer has the `opencode-paid` key, so three more test lines must change or `Get-SlopRouteBadge` will throw `unknown route kind`:

- `tests/slop-route-check.ps1:21`: delete `providerTier='free'` from the hashtable.
- `tests/slop-route-check.ps1:42`: change `Get-SlopRouteBadge -Kind 'opencode-paid'` to `Get-SlopRouteBadge -Kind 'opencode-remote'`; the expected badge string is unchanged.
- `tests/slop-route-check.ps1:52`: delete the whole line `(Get-SlopRouteCatalog)['opencode-paid'].TermsRequired | Should -BeTrue`.

After the edits, `src/Slop.Route.ps1` must have no `opencode-paid` or `providerTier` matches, and `tests/slop-route-check.ps1` must have no `providerTier` matches. The string `opencode-paid` intentionally remains only in the new catalog-absence assertion; a blanket "no matches" check would contradict that assertion.

```powershell
Select-String -Path src/Slop.Route.ps1 -Pattern 'opencode-paid|providerTier'
Select-String -Path tests/slop-route-check.ps1 -Pattern 'providerTier'
```

- [ ] **Step 4: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-route-check.ps1 -Output Detailed"`
Expected: all route tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Slop.Route.ps1 tests/slop-route-check.ps1
git commit -m "feat: drop opencode-paid route kind"
```

---

### Task 4: Tier-aware UI, onboarding and copy

**Files:**
- Modify: `src/Slop.Onboarding.ps1:139-166,306-333,335-345,347-380`
- Modify: `src/Slop.ps1:178,222,1111,1208-1222,1386-1395,2080-2091`
- Modify: `src/Slop.Surfaces.ps1:6-10,30-35,55-61`
- Modify: `src/Slop.Disclosure.ps1:43-50`
- Test: `tests/slop-onboarding-check.ps1`
- Test: `tests/slop-surfaces-check.ps1`
- Test: `tests/slop-shell-check.ps1`

- [ ] **Step 1: Write failing surface and onboarding tests**

Replace the Brain row in `tests/slop-surfaces-check.ps1:30` with:

```powershell
            Brain     = @{ Status='BrainStatusText';     Editable=@('BrainTypeCombo','BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo'); Actions=@('BrainSaveButton','BrainBack') }
```

Append to `tests/slop-surfaces-check.ps1`:

```powershell
    It 'names destinations by tier instead of free or paid' {
        $map = Get-SlopDestinationMap
        $map.Brain | Should -Contain 'Tier'
        $map.Brain | Should -Not -Contain 'Local vs remote'
        ($map.Values -join ' ') | Should -Not -Match '(?i)\bfree\b|\bpaid\b'
    }

    It 'points deletion copy at the in-app data folder' {
        $pattern = [regex]::Escape('data\config.json')
        Get-SlopDeletionScope -Action 'local-data' | ForEach-Object { $_.Scope } |
            Should -Match $pattern
        Get-SlopDeletionCopy -Action 'local-data' | Should -Not -Match 'LOCALAPPDATA'
    }
```

Append to `tests/slop-onboarding-check.ps1`:

```powershell
    It 'does not offer a paid-provider checkbox' {
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
        $src | Should -Not -Match 'PaidProvider'
        $src | Should -Not -Match 'providerTier'
        $src | Should -Not -Match 'opencode-paid'
    }

    It 'pre-fills the OpenCode model from the shared tier catalog' {
        $opts = @(Get-SlopBrainModelOptions -Brain 'opencode')
        $opts | Should -Be @('big-pickle','beam-free')
    }
```

Also update the existing `generates the swatches...` test: it still asserts the `BrainNote` copy that Step 3 deletes. Replace that assertion with:

```powershell
        $src | Should -Not -Match 'BrainNote'
        $src | Should -Match 'Tier 1 - built-in local Qwen; Tier 2 - OpenCode'
```

Append to `tests/slop-shell-check.ps1`. The removed label is the old `3=custom` claim; Tier 3 stays reserved and must not be given a brain or model catalog in this change.

```powershell
Assert-True ($src -match 'Get-SlopBrainOrder') 'Brain combo uses the ordered tier list'
Assert-True ($src -match 'Get-SlopBrainModelOptions -Brain') 'model options come from the shared catalog'
Assert-True ($src -notmatch '\$BrainModelBox\.Text = if \(\[string\]::IsNullOrWhiteSpace') 'Brain model box no longer accepts an off-tier saved model'
Assert-True ($src -notmatch 'Tier \(1=built-in, 2=OpenCode, 3=custom\)') 'no tier-3 label remains'
Assert-True ($src -match 'Join-Path \(Split-Path \$PSScriptRoot -Parent\) ''run\.vbs''') 'autostart targets the VBS launcher'
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-onboarding-check.ps1,tests/slop-surfaces-check.ps1,tests/slop-shell-check.ps1 -Output Detailed"`
Expected: FAIL for the new assertions — paid checkbox still present, surfaces still advertise removed controls, autostart still points at `launch.cmd`.

- [ ] **Step 3: Update the onboarding wizard**

In `src/Slop.Onboarding.ps1`, delete lines 145-146 (the `PaidProvider` `CheckBox`) and the `BrainNote` block at lines 166-168. `BrainNote` has no `FindName` wiring in the current source; after the edit, this must print no matches:

```powershell
Select-String -Path src/Slop.Onboarding.ps1 -Pattern 'PaidProvider|BrainNote|providerTier|opencode-paid'
```

Replace lines 328-333 with:

```powershell
    Update-SlopBrainFields
```

Replace the `TermsButton` handler at lines 336-345 with:

```powershell
    $TermsButton.Add_Click({ param($s,$e)
        if (Get-Command Show-SlopDisclosure -ErrorAction SilentlyContinue) {
            $kind = if ($BrainOpenCodeRemote.IsChecked) { 'opencode-remote' } else { 'opencode-local' }
            # No verified provider terms URL is bundled. An empty value makes the
            # disclosure state plainly that retention/training terms are unknown.
            Show-SlopDisclosure -Route @{ Kind=$kind; Provider=[string]$ProviderBox.Text; Model=[string]$RouteModelBox.Text } | Out-Null
        }
    })
```

Replace lines 364-380 (the whole `elseif` OpenCode branch) with:

```powershell
        elseif ($BrainOpenCodeLocal.IsChecked -or $BrainOpenCodeRemote.IsChecked) {
            $result.brain = 'opencode'
            $result.providerLocality = if ($BrainOpenCodeLocal.IsChecked) { 'local' } else { 'remote' }
            $result.termsUrl = ''
            $result.provider = $ProviderBox.Text.Trim()
            $result.model = $RouteModelBox.Text.Trim()
            $result.modelName = $RouteModelBox.Text.Trim()
            $result.agentId = $AgentBox.Text.Trim()
            $result.agent = @{}
            $result.capabilityProfile = [string]$ProfileCombo.SelectedItem
            $result.openCodeBaseUrl = if ($Config.openCodeBaseUrl) { [string]$Config.openCodeBaseUrl } else { 'http://127.0.0.1:28894' }
            $serviceJson = Join-Path $env:USERPROFILE '.config/opencode/service.json'
            $result.serviceConfigPath = if (Test-Path -LiteralPath $serviceJson) { $serviceJson } else { '' }
        }
```

Keep `$RouteModelBox.Text` pre-filled from line 240; change that line to use the catalog so the wizard never shows an option that the Brain panel cannot reproduce:

```powershell
    $RouteModelBox.Text = if ($Config.model) { [string]$Config.model } else { @(Get-SlopBrainModelOptions -Brain 'opencode')[0] }
```

- [ ] **Step 4: Update Settings and route copy**

In `src/Slop.ps1`:
- line 1111: delete the whole argument line that reads `-ProviderTier 'free'` (including its trailing PowerShell line-continuation backtick) from the `Set-SlopConfigBrain` call in `Save-SlopBrain`. `Set-SlopConfigBrain` no longer accepts that parameter (Task 2), so leaving it breaks every Brain save.
- line 222: replace the label text with `Brain tier - 1 = built-in local, 2 = OpenCode` (keep the element name `BrainTypeCombo`).
- line 1208: `Set-SlopComboItems -Combo $BrainTypeCombo -Items @( Get-SlopBrainOrder ) -Selected ([string]$cfg.brain)`
- lines 1211-1219: replace the `switch` with:

```powershell
    $BrainModelBox.Items.Clear()
    foreach ($m in @( Get-SlopBrainModelOptions -Brain ([string]$cfg.brain) )) {
        [void]$BrainModelBox.Items.Add($m)
    }
```

- line 1222: the current assignment sets the combo text from `$cfg.model` even when that value is outside the selected tier. The default config is `brain='builtin'` with `model='big-pickle'`, so without this edit tier 1 displays a tier 2 model. Replace line 1222 with:

```powershell
    $modelItems = @($BrainModelBox.Items)
    $selectedModel = [string]$cfg.model
    if ($modelItems -notcontains $selectedModel) { $selectedModel = [string]$cfg.modelName }
    if ($modelItems -contains $selectedModel) { $BrainModelBox.Text = $selectedModel }
    elseif ($modelItems.Count -gt 0) { $BrainModelBox.SelectedIndex = 0 }
```

- lines 1388-1394: replace with:

```powershell
    $BrainModelBox.Items.Clear()
    foreach ($m in @( Get-SlopBrainModelOptions -Brain ([string]$BrainTypeCombo.SelectedItem) )) {
        [void]$BrainModelBox.Items.Add($m)
    }
    if ($BrainModelBox.Items.Count -gt 0) { $BrainModelBox.SelectedIndex = 0 }
```

- line 178: replace the data-location text with `<TextBlock Text="Data location: {app}\data (inside the folder you chose during setup)" ... />` keeping the existing `Foreground`, `FontSize`, `TextWrapping` and `Margin`.

- lines 2082-2083: replace with:

```powershell
    $launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'run.vbs'
    if (-not (Test-Path -LiteralPath $launcher)) { return }  # developer run, not installed
```

- [ ] **Step 5: Update headless surface contracts and copy**

In `src/Slop.Surfaces.ps1`:
- line 8: `'Brain     = @('Tier','Provider','Model','Agent','Capability profile','Effective model')'`
- line 33: remove `'BrainLocalityCombo'` from the `Editable` array.
- line 48: change the scope string to `'{app}\data\config.json and persona.md'`. The RED test above matches `data\config.json`, so the shorter proposal in the original draft would contradict it.

In `src/Slop.Disclosure.ps1`, change line 48 inside `Get-SlopDeletionCopy` so the function reads:

```powershell
function Get-SlopDeletionCopy {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    switch ($Action) {
        'conversation' { return 'Clear conversation removes the Sloppy transcript only. The OpenCode session and its stored messages remain.' }
        'session'      { return 'Delete OpenCode session removes that session and its child sessions from OpenCode''s local store. It does not mean the provider deleted its copy of a prompt or transcript.' }
        'local-data'   { return 'Clear Sloppy local data removes config.json and persona.md from the data folder inside your Sloppy install. It does not delete OpenCode sessions or provider data.' }
    }
}
```

- [ ] **Step 6: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-onboarding-check.ps1,tests/slop-surfaces-check.ps1,tests/slop-shell-check.ps1 -Output Detailed"`
Expected: all PASS. The shell suite also asserts the old launcher assertion at line 221 still passes — no change needed there because `install.ps1` is rewritten in Task 8.

- [ ] **Step 7: Commit**

```bash
git add src/Slop.Onboarding.ps1 src/Slop.ps1 src/Slop.Surfaces.ps1 src/Slop.Disclosure.ps1 tests/slop-onboarding-check.ps1 tests/slop-surfaces-check.ps1 tests/slop-shell-check.ps1
git commit -m "feat: make tier changes drive model options and remove paid-provider UI"
```

---

### Task 5: Preflight and live verifier use the app root

**Files:**
- Modify: `tools/slop-preflight.ps1:1-22`
- Modify: `tools/verify-motion.ps1:273-300,314-327,444,508-509,702`
- Test: `tests/slop-preflight-check.ps1`

- [ ] **Step 1: Write failing preflight tests**

Append to `tests/slop-preflight-check.ps1`:

```powershell
    It 'resolves the app root from the hidden override when no root is passed' {
        $previous = $env:SLOP_TEST_INSTALL_ROOT
        try {
            $env:SLOP_TEST_INSTALL_ROOT = $TestDrive
            $report = Invoke-SlopPreflight -ConfigPath (Join-Path $TestDrive 'config.json')
            $report.InstallRoot | Should -Be ([IO.Path]::GetFullPath($TestDrive))
        }
        finally { $env:SLOP_TEST_INSTALL_ROOT = $previous }
    }
```

Append static assertions to the same file:

```powershell
    It 'does not read SLOP_TEST_APPDATA anywhere in tools' {
        $files = Get-ChildItem (Join-Path $PSScriptRoot '../tools') -Filter '*.ps1'
        foreach ($f in $files) {
            (Get-Content $f.FullName -Raw) | Should -Not -Match 'SLOP_TEST_APPDATA'
        }
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-preflight-check.ps1 -Output Detailed"`
Expected: FAIL — `Invoke-SlopPreflight` has no `InstallRoot` result key and `verify-motion.ps1` still sets `SLOP_TEST_APPDATA`.

- [ ] **Step 3: Make preflight root explicit in its result**

In `tools/slop-preflight.ps1`, change line 20 from:

```powershell
    $root = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { Get-SlopVoiceInstallRoot } else { [IO.Path]::GetFullPath($InstallRoot) }
```

to:

```powershell
    $root = if ([string]::IsNullOrWhiteSpace($InstallRoot)) { Get-SlopAppRoot } else { [IO.Path]::GetFullPath($InstallRoot) }
```

In the report hashtable returned by `Invoke-SlopPreflight`, add `InstallRoot=$root` and keep the existing `Lines` and `Errors` keys unchanged. (Locate the `return @{` in that function; add the key on its own line.)

- [ ] **Step 4: Migrate the live verifier**

In `tools/verify-motion.ps1`:
- lines 273-274 comment: replace with `# Isolated Sloppy install root. LOCALAPPDATA is left alone on purpose.`
- line 276: `$installRoot = Join-Path $dir 'install'`
- lines 277-283: create `$installRoot\data`, write `config.json` there, then remove the `$env:SLOP_TEST_APPDATA` assignment.
- line 284: replace with `$env:SLOP_TEST_INSTALL_ROOT = $installRoot`
- before line 284: capture `$script:OriginalTestInstallRoot = $env:SLOP_TEST_INSTALL_ROOT` so teardown can restore it.
- lines 294-299: remove the `OriginalLocalAppData` capture and the `%LOCALAPPDATA%\Programs\Sloppy` probe. Keep the bundled-server/model existence check, but point it at `$installRoot` already defined in Step 3.
- lines 314-326: build the stand-in under `$installRoot`, not under `LOCALAPPDATA`: set `$standInRoot = $installRoot`, create the runtime junction at `$installRoot\runtime\llama-b12676-bin-win-cuda-13.5-x64`, and the model symlink at `$installRoot\runtime\models\Qwen3.5-2B-Q4_K_M.gguf` (plus the optional mmproj link there). Runtime paths now come from `Get-SlopAppRoot`, so the stand-in must live under the same root as `data\config.json`.
- line 327: delete `$env:LOCALAPPDATA = $runtimeEnv` entirely; no production path reads `LOCALAPPDATA` after Task 1.
- line 444: remove `'BrainLocalityCombo'` and `'BrainTierCombo'` from the control-name array; both controls were removed from the app before this plan.
- line 508: delete `Set-UiaCombo 'BrainLocalityCombo' 'local'`.
- line 509: delete `Set-UiaCombo 'BrainTierCombo' 'free'`.
- line 702: restore `$script:OriginalTestInstallRoot` into `SLOP_TEST_INSTALL_ROOT`; do not restore `LOCALAPPDATA`.

- [ ] **Step 5: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-preflight-check.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add tools/slop-preflight.ps1 tools/verify-motion.ps1 tests/slop-preflight-check.ps1
git commit -m "feat: move preflight and live verifier to the canonical install root"
```

---

### Task 6: Pinned asset manifest and headless fetch helper

**Files:**
- Create: `tools/slop-assets.json`
- Create: `tools/slop-fetch-assets.ps1`
- Test: `tests/slop-installer-check.ps1` (create)

- [ ] **Step 1: Write the failing installer contract suite**

Create `tests/slop-installer-check.ps1`:

```powershell
#requires -Version 7.6
Describe 'Slop installer contracts' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
    }

    It 'pins both large assets with a destination and SHA-256' {
        $manifest = Get-Content (Join-Path $root 'tools/slop-assets.json') -Raw | ConvertFrom-Json
        $manifest.version | Should -Be 1
        $manifest.release | Should -Be 'v0.3.0'
        @($manifest.assets).Count | Should -Be 2
        foreach ($a in $manifest.assets) {
            $a.sha256 | Should -Match '^[0-9A-F]{64}$'
            $a.destination | Should -Not -Match '^\.'
            $a.url | Should -Match '^https://github\.com/shahriarhaqueabir/Sloppy/releases/download/v0\.3\.0/'
        }
        @($manifest.assets.name) | Should -Be @('Qwen3.5-2B-Q4_K_M.gguf','ggml-small.bin')
    }

    It 'hashes the actual bundled asset sizes' {
        $manifest = Get-Content (Join-Path $root 'tools/slop-assets.json') -Raw | ConvertFrom-Json
        $qwen = $manifest.assets | Where-Object { $_.name -eq 'Qwen3.5-2B-Q4_K_M.gguf' }
        $qwen.bytes | Should -Be 1312164352
        $qwen.sha256 | Should -Be '4E936E9D3DEDC45FA4CADB4A271FA50F8D6F3DB3BE0EADDC01DC4D6D356AA327'
        $whisper = $manifest.assets | Where-Object { $_.name -eq 'ggml-small.bin' }
        $whisper.bytes | Should -Be 487601967
        $whisper.sha256 | Should -Be '1BE3A9B2063867B937E64E2EC7483364A79917E157FA98C5D94B5C1FFFEA987B'
    }

    It 'fetches assets headlessly with checksum verification' {
        $src = Get-Content (Join-Path $root 'tools/slop-fetch-assets.ps1') -Raw
        $src | Should -Match 'Invoke-WebRequest'
        $src | Should -Match 'Get-FileHash -Algorithm SHA256'
        $src | Should -Match 'SLOP_TEST_ASSET_FIXTURES'
        $src | Should -Match '\.part'
        $src | Should -Match 'exit 1'
    }
}
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: FAIL — manifest and helper do not exist.

- [ ] **Step 3: Create the manifest**

Create `tools/slop-assets.json`:

```json
{
  "version": 1,
  "release": "v0.3.0",
  "baseUrl": "https://github.com/shahriarhaqueabir/Sloppy/releases/download/v0.3.0",
  "assets": [
    {
      "name": "Qwen3.5-2B-Q4_K_M.gguf",
      "url": "https://github.com/shahriarhaqueabir/Sloppy/releases/download/v0.3.0/Qwen3.5-2B-Q4_K_M.gguf",
      "destination": "runtime\\models\\Qwen3.5-2B-Q4_K_M.gguf",
      "bytes": 1312164352,
      "sha256": "4E936E9D3DEDC45FA4CADB4A271FA50F8D6F3DB3BE0EADDC01DC4D6D356AA327"
    },
    {
      "name": "ggml-small.bin",
      "url": "https://github.com/shahriarhaqueabir/Sloppy/releases/download/v0.3.0/ggml-small.bin",
      "destination": "runtime\\whisper\\models\\ggml-small.bin",
      "bytes": 487601967,
      "sha256": "1BE3A9B2063867B937E64E2EC7483364A79917E157FA98C5D94B5C1FFFEA987B"
    }
  ]
}
```

- [ ] **Step 4: Create the fetch helper**

Create `tools/slop-fetch-assets.ps1`:

```powershell
# Headless post-install asset fetcher. Never writes outside the chosen install root.
#requires -Version 7.6
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ManifestPath
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallRoot)
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

function Get-SlopAssetHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-SlopAsset {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sha256)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Get-SlopAssetHash -Path $Path) -eq $Sha256.ToUpperInvariant())
}

foreach ($asset in $manifest.assets) {
    $dest = Join-Path $root $asset.destination
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    if (Test-SlopAsset -Path $dest -Sha256 $asset.sha256) {
        Write-Host "Sloppy asset ready: $($asset.name)"
        continue
    }

    $copied = $false
    $fixtures = $env:SLOP_TEST_ASSET_FIXTURES
    if (-not [string]::IsNullOrWhiteSpace($fixtures)) {
        $fixturePath = Join-Path $fixtures $asset.name
        if (Test-SlopAsset -Path $fixturePath -Sha256 $asset.sha256) {
            Copy-Item -LiteralPath $fixturePath -Destination $dest -Force
            $copied = $true
        }
    }
    if (-not $copied) {
        $part = "$dest.part"
        try {
            Write-Host "Downloading $($asset.name) from $($asset.url)"
            Invoke-WebRequest -Uri $asset.url -OutFile $part -UseBasicParsing
            if (-not (Test-SlopAsset -Path $part -Sha256 $asset.sha256)) {
                throw "checksum mismatch for $($asset.name); expected $($asset.sha256)"
            }
            Move-Item -LiteralPath $part -Destination $dest -Force
            $copied = $true
        }
        catch {
            Write-Warning "Could not fetch $($asset.name): $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        }
    }
    if (-not $copied) {
        [Console]::Error.WriteLine("Sloppy could not install $($asset.name) from $($asset.url); install incomplete. Re-run setup to retry.")
        exit 1
    }
}
Write-Host 'Sloppy assets verified.'
```

The `SLOP_TEST_ASSET_FIXTURES` branch is hidden CI plumbing; it is never shown in the UI or README.

- [ ] **Step 5: Confirm GREEN with local fixtures**

Verify the failure path with a deliberately wrong checksum. Run this block directly in the repo's pwsh session (no nested shell):

```powershell
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('slop-asset-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$m = Join-Path $tmp 'm.json'
@{
    version = 1
    release = 'v0.3.0'
    assets  = @(@{
        name        = 'tiny.bin'
        url         = 'https://example.invalid/tiny.bin'
        destination = 'runtime\models\tiny.bin'
        sha256      = '0000000000000000000000000000000000000000000000000000000000000000'
    })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $m -Encoding utf8
& '.\tools\slop-fetch-assets.ps1' -InstallRoot $tmp -ManifestPath $m 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'expected checksum failure' }
$dest = Join-Path $tmp 'runtime\models\tiny.bin'
if (Test-Path -LiteralPath $dest) { throw 'a failed download left a destination behind' }
if (Test-Path -LiteralPath "$dest.part") { throw 'a failed download left a .part behind' }
Write-Output 'ASSET_FAILURE_PATH_OK'
Remove-Item $tmp -Recurse -Force
```

Expected: `ASSET_FAILURE_PATH_OK`, proving a mismatch exits non-zero and leaves neither a destination nor a `.part` file. Note this probe cannot use the real large assets; checksum verification is proven with a deliberately wrong hash, and the real hashes are asserted by the manifest test above.

- [ ] **Step 6: Confirm GREEN for the contract suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: all three tests PASS.

- [ ] **Step 7: Commit**

```bash
git add tools/slop-assets.json tools/slop-fetch-assets.ps1 tests/slop-installer-check.ps1
git commit -m "feat: pin installer asset manifest and checksum-verified fetch helper"
```

---

### Task 7: Inno Setup single-folder installer

**Files:**
- Create: `installer/Sloppy.iss`
- Test: `tests/slop-installer-check.ps1`

- [ ] **Step 1: Write failing installer structure tests**

Append to `tests/slop-installer-check.ps1` inside the `Describe` block:

```powershell
    It 'uses Inno Setup with a user-chosen folder and an unchecked desktop task' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match 'DefaultDirName=\{autopf\}\\Sloppy'
        $iss | Should -Match 'PrivilegesRequired=lowest'
        $iss | Should -Match 'Name: desktopicon;.*Flags: unchecked'
        $iss | Should -Match '\{autodesktop\}\\Sloppy'
        $iss | Should -Match '\{group\}\\Sloppy'
        $iss | Should -Match '/DIR=' # documented in the installer comment header
    }

    It 'launches headlessly and protects user data on uninstall' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match '\{sys\}\\wscript\.exe'
        $iss | Should -Match 'run\.vbs'
        $iss | Should -Match 'Name: "?\{app\}\\data"?; Flags: uninsneveruninstall'
        $iss | Should -Match 'CurStepChanged'
        $iss | Should -Match 'SW_HIDE'
        $iss | Should -Not -Match 'pwsh\.exe""' # no direct PowerShell shortcut
    }

    It 'boots PowerShell before the post-install helper' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match 'Ensure-SlopPowerShell'
        $iss | Should -Match 'Microsoft\.PowerShell'
        $iss | Should -Match 'slop-fetch-assets\.ps1'
        $iss | Should -Match 'Get-PreviousSlopInstallRoot'
        $iss | Should -Match '\.sloppy-install\.json'
        $iss | Should -Match 'Key := ExpandConstant'
        $iss | Should -Match "FileSearch\('pwsh\.exe'"
        $iss | Should -Not -Match 'FileOrCmdExists|ACS_Quote'
    }

    It 'bundles only runtime source directories that exist in the repo' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $missing = @()
        foreach ($m in [regex]::Matches($iss, '(?m)^Source: "\.\.\\([^"*]+)\\\*"')) {
            $rel = $m.Groups[1].Value
            if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) { $missing += $rel }
        }
        $missing | Should -BeEmpty
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: FAIL — `installer/Sloppy.iss` does not exist.

- [ ] **Step 3: Create the Inno script**

Create `installer/Sloppy.iss`:

```pascal
; Single-folder Sloppy installer. Compile with Inno Setup 6.5.4+.
; GUI: double-click SloppySetup.exe.
; CLI: SloppySetup.exe /DIR="D:\Sloppy" /TASKS=desktopicon /VERYSILENT
; install.ps1 maps -InstallDir to /DIR= and -DesktopShortcut to /TASKS=desktopicon.
#define MyAppName "Sloppy"
#define MyAppVersion "0.3.0"
#define MyAppPublisher "shahriarhaqueabir"
#define MyAppExeName "run.vbs"
#define MyAppId "{{B8E1A0C4-6D4E-4A4B-9C7B-2F1E0D3A5B71}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Sloppy
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=..\artifacts
OutputBaseFilename=SloppySetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableDirPage=no
UninstallDisplayName={#MyAppName} {#MyAppVersion}
AllowNoIcons=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Dirs]
Name: "{app}\data"; Flags: uninsneveruninstall

[Files]
Source: "..\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\llama-b12676-bin-win-cpu-x64\*"; DestDir: "{app}\runtime\llama-b12676-bin-win-cpu-x64"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\llama-b12676-bin-win-cuda-13.5-x64\*"; DestDir: "{app}\runtime\llama-b12676-bin-win-cuda-13.5-x64"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runtime\whisper\*"; DestDir: "{app}\runtime\whisper"; Excludes: "models\ggml-small.bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\run.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\run.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"
Name: "{autodesktop}\Sloppy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\run.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon

[Code]
function SlopJsonString(const S: String): String;
var
  T: String;
begin
  { Backslash is not an escape character in Pascal string literals. }
  T := S;
  StringChangeEx(T, '\', '\\', True);
  StringChangeEx(T, '"', '\"', True);
  Result := '"' + T + '"';
end;

function Get-PreviousSlopInstallRoot(out Root: String): Boolean;
var
  Key: String;
begin
  Result := False;
  Root := '';
  { ISPP emits {{GUID}; ExpandConstant collapses it to the real {GUID} key. }
  Key := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}_is1');
  if RegQueryStringValue(HKCU, Key, 'InstallLocation', Root) then
    Result := DirExists(Root)
  else if RegQueryStringValue(HKLM, Key, 'InstallLocation', Root) then
    Result := DirExists(Root);
end;

function Locate-SlopPowerShell: String;
var
  Candidate: String;
begin
  Result := '';
  { FileOrCmdExists is not an Inno support function; FileSearch is. }
  Candidate := FileSearch('pwsh.exe', GetEnv('Path'));
  if Candidate <> '' then
  begin
    Result := Candidate;
    Exit;
  end;
  Candidate := AddBackslash(GetEnv('ProgramFiles')) + 'PowerShell\7\pwsh.exe';
  if FileExists(Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;
  Candidate := AddBackslash(GetEnv('LOCALAPPDATA')) + 'Programs\PowerShell\7\pwsh.exe';
  if FileExists(Candidate) then Result := Candidate;
end;

function Ensure-SlopPowerShell: Boolean;
var
  ResultCode: Integer;
begin
  if Locate-SlopPowerShell <> '' then
  begin
    Result := True;
    Exit;
  end;
  if not Exec('winget.exe',
              'install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements',
              '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := False;
    Exit;
  end;
  Result := Locate-SlopPowerShell <> '';
end;

procedure Write-SlopInstallMarker;
var
  Marker: String;
  Previous: String;
begin
  Marker := AddBackslash(ExpandConstant('{app}')) + '.sloppy-install.json';
  if Get-PreviousSlopInstallRoot(Previous) then
    SaveStringToFile(Marker,
      '{ "version": 1, "appVersion": ' + SlopJsonString('{#MyAppVersion}') +
      ', "root": ' + SlopJsonString(ExpandConstant('{app}')) +
      ', "upgradedFrom": ' + SlopJsonString(Previous) + ' }', False)
  else
    SaveStringToFile(Marker,
      '{ "version": 1, "appVersion": ' + SlopJsonString('{#MyAppVersion}') +
      ', "root": ' + SlopJsonString(ExpandConstant('{app}')) + ' }', False);
end;

procedure Fetch-SlopAssets;
var
  PowerShellExe: String;
  Params: String;
  ResultCode: Integer;
begin
  PowerShellExe := Locate-SlopPowerShell;
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
            AddBackslash(ExpandConstant('{app}')) + 'tools\slop-fetch-assets.ps1" -InstallRoot "' +
            ExpandConstant('{app}') + '" -ManifestPath "' +
            AddBackslash(ExpandConstant('{app}')) + 'tools\slop-assets.json"';
  if not Exec(PowerShellExe, Params, ExpandConstant('{app}'), SW_HIDE,
              ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    raise Exception.Create('Sloppy could not download its models. Check your connection and re-run setup.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not Ensure-SlopPowerShell then
      raise Exception.Create('Sloppy needs PowerShell 7.6 or newer. Install it, then re-run setup.');
  end;
  if CurStep = ssPostInstall then
  begin
    Write-SlopInstallMarker;
    Fetch-SlopAssets;
  end;
end;
```

Hashing is done by the PowerShell helper, so the Pascal `[Code]` block deliberately has no hashing function.

- [ ] **Step 4: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: all installer tests PASS.

- [ ] **Step 5: Compile-check when Inno is available**

`ISCC` is not installed on this machine. Do not install system-level tooling without explicit approval. In CI (Task 9) the compile is authoritative. Locally, verify only the static contract above and report "Inno compile not run locally (ISCC absent)".

- [ ] **Step 6: Commit**

```bash
git add installer/Sloppy.iss tests/slop-installer-check.ps1
git commit -m "feat: add single-folder Inno Setup installer script"
```

---

### Task 8: Shared install wrappers and headless launchers

**Files:**
- Modify: `install.ps1`
- Modify: `install.cmd`
- Modify: `run.vbs`
- Modify: `run.cmd`
- Test: `tests/slop-shell-check.ps1`
- Test: `tests/slop-installer-check.ps1`

- [ ] **Step 1: Write failing wrapper tests**

Append to `tests/slop-installer-check.ps1`:

```powershell
    It 'maps the documented one-liner parameters to Inno switches' {
        $src = Get-Content (Join-Path $root 'install.ps1') -Raw
        $src | Should -Match 'param\('
        $src | Should -Match '\[string\]\$InstallDir'
        $src | Should -Match '\[switch\]\$DesktopShortcut'
        $src | Should -Match '/DIR='
        $src | Should -Match '/TASKS=desktopicon'
        $src | Should -Match '/VERYSILENT'
        $src | Should -Match 'SloppySetup\.exe'
        $src | Should -Not -Match 'git clone'
    }

    It 'launches from the script folder with no console window' {
        $vbs = Get-Content (Join-Path $root 'run.vbs') -Raw
        $vbs | Should -Match 'WScript\.ScriptFullName'
        $vbs | Should -Match '-WindowStyle Hidden'
        $vbs | Should -Match ', 0, False'
        $cmd = Get-Content (Join-Path $root 'run.cmd') -Raw
        $cmd | Should -Match 'wscript "%~dp0run\.vbs"'
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: FAIL — `install.ps1` still clones with git, `run.vbs` uses `CurrentDirectory`.

- [ ] **Step 3: Rewrite `install.ps1` as a thin wrapper**

Replace the whole file:

```powershell
<#
.SYNOPSIS
  Downloads and runs the single-folder Sloppy installer.
.DESCRIPTION
  One behavior for the double-click installer and the PowerShell one-liner.
  With -InstallDir the wizard is suppressed; without it the Inno folder picker
  is shown. -DesktopShortcut opts into the otherwise-unchecked desktop task.
.EXAMPLE
  $installer = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1
  & ([scriptblock]::Create($installer)) -InstallDir 'D:\Sloppy' -DesktopShortcut
#>
param(
    [string]$InstallDir,
    [switch]$DesktopShortcut,
    [string]$ReleaseTag = 'v0.3.0'
)
$ErrorActionPreference = 'Stop'

$base = 'https://github.com/shahriarhaqueabir/Sloppy/releases/download/' + $ReleaseTag
$setupUrl = $base + '/SloppySetup.exe'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('sloppy-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$setup = Join-Path $temp 'SloppySetup.exe'

try {
    Write-Host 'Downloading the Sloppy installer...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $setupUrl -OutFile $setup -UseBasicParsing

    $argsList = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $argsList.Add('/DIR="' + [IO.Path]::GetFullPath($InstallDir) + '"')
        $argsList.Add('/VERYSILENT')
        $argsList.Add('/SUPPRESSMSGBOXES')
    }
    if ($DesktopShortcut) { $argsList.Add('/TASKS=desktopicon') }
    else { $argsList.Add('/TASKS=') }

    $proc = Start-Process -FilePath $setup -ArgumentList $argsList.ToArray() -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Sloppy setup exited with code $($proc.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
```

- [ ] **Step 4: Simplify `install.cmd` and harden the launchers**

Replace `install.cmd`:

```bat
@echo off
setlocal
title Sloppy installer
echo.
echo  Sloppy installer
echo  =================
echo.
where pwsh >nul 2>&1
if errorlevel 1 (
  echo Sloppy needs PowerShell 7.6 or newer.
  echo Install it from https://aka.ms/powershell then re-run.
  pause
  exit /b 1
)

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$i = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1; ^& ([scriptblock]::Create($i))"
if errorlevel 1 (
  echo Sloppy setup did not complete.
  pause
  exit /b 1
)
endlocal
```

Replace `run.vbs`:

```vbs
' Headless launcher for Sloppy (no PowerShell console window).
Set Fso = CreateObject("Scripting.FileSystemObject")
AppRoot = Fso.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh -WindowStyle Hidden -STA -NoProfile -File """ & AppRoot & "\src\Slop.ps1""", 0, False
Set WshShell = Nothing
Set Fso = Nothing
```

Keep `run.cmd` unchanged:

```bat
@echo off
REM Headless launcher for Sloppy (no PowerShell console window).
REM Uses a VBScript wrapper so the console never flashes.
wscript "%~dp0run.vbs"
```

- In `tests/slop-shell-check.ps1`, replace lines 219-221. The thin `install.ps1` no longer contains shortcut code, so these assertions must read the Inno script created in Task 7:

```powershell
$iss = Get-Content (Join-Path $PSScriptRoot '../installer/Sloppy.iss') -Raw
Assert-True ($iss -match 'Filename: "\{sys\}\\wscript\.exe"') 'installed shortcut uses wscript.exe'
Assert-True ($iss -match 'Parameters: """\{app\}\\run\.vbs"""') 'installed shortcut uses the headless VBS launcher'
Assert-True ($iss -notmatch 'Filename: "\{sys\}\\pwsh\.exe"') 'installed shortcut does not launch pwsh directly'
```

- [ ] **Step 5: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1,tests/slop-shell-check.ps1 -Output Detailed"`
Expected: all PASS. The shortcut assertions now read `installer/Sloppy.iss`; `install.ps1` is only a downloader.

- [ ] **Step 6: Commit**

```bash
git add install.ps1 install.cmd run.vbs run.cmd tests/slop-installer-check.ps1 tests/slop-shell-check.ps1
git commit -m "feat: share one installer path between the one-liner and GUI"
```

---

### Task 9: Tag-triggered release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Test: `tests/slop-installer-check.ps1`

- [ ] **Step 1: Write failing release contract tests**

Append to `tests/slop-installer-check.ps1`:

```powershell
    It 'builds and publishes the installer from a tag' {
        $wf = Get-Content (Join-Path $root '.github/workflows/release.yml') -Raw
        $wf | Should -Match 'on:'
        $wf | Should -Match 'tags:'
        $wf | Should -Match 'InnoSetup'
        $wf | Should -Match '--version 6\.5\.4'
        $wf | Should -Match 'ISCC\.exe'
        $wf | Should -Match 'slop-fetch-assets\.ps1'
        $wf | Should -Match 'SLOP_TEST_ASSET_FIXTURES'
        $wf | Should -Match 'gh release view'
        $wf | Should -Match 'gh release create'
        $wf | Should -Match 'gh release upload'
        $wf | Should -Match 'SHA256SUMS\.txt'
        $wf | Should -Match 'lfs: true'
    }
```

- [ ] **Step 2: Confirm RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: FAIL — workflow does not exist.

- [ ] **Step 3: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release installer

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - name: Pull LFS assets
        shell: pwsh
        run: git lfs pull

      - name: Pin Inno Setup 6.5.4
        shell: pwsh
        run: choco install InnoSetup --version 6.5.4 --yes --no-progress

      - name: Verify pinned asset hashes
        shell: pwsh
        run: |
          $manifest = Get-Content tools/slop-assets.json -Raw | ConvertFrom-Json
          foreach ($a in $manifest.assets) {
            $p = Join-Path $pwd $a.destination
            if (-not (Test-Path -LiteralPath $p)) { throw "missing LFS asset: $($a.name)" }
            $actual = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actual -ne $a.sha256.ToUpperInvariant()) { throw "hash mismatch: $($a.name)" }
            "$($a.sha256)  $($a.name)" | Add-Content SHA256SUMS.txt
          }

      - name: Compile installer
        shell: pwsh
        run: |
          $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
          if (-not (Test-Path $iscc)) { $iscc = "$env:ProgramFiles\Inno Setup 6\ISCC.exe" }
          if (-not (Test-Path $iscc)) { throw 'ISCC.exe not found' }
          & $iscc installer/Sloppy.iss
          if ($LASTEXITCODE -ne 0) { throw "ISCC failed with $LASTEXITCODE" }

      - name: Silent-install smoke test
        shell: pwsh
        run: |
          $dir = Join-Path $env:RUNNER_TEMP 'sloppy-smoke'
          New-Item -ItemType Directory -Force -Path $dir | Out-Null
          $fixtures = Join-Path $env:RUNNER_TEMP 'sloppy-fixtures'
          New-Item -ItemType Directory -Force -Path $fixtures | Out-Null
          Copy-Item runtime\models\Qwen3.5-2B-Q4_K_M.gguf $fixtures -Force
          Copy-Item runtime\whisper\models\ggml-small.bin $fixtures -Force
          $env:SLOP_TEST_ASSET_FIXTURES = $fixtures
          $setup = Join-Path $pwd 'artifacts\SloppySetup.exe'
          & $setup /DIR="$dir" /TASKS=desktopicon /VERYSILENT /SUPPRESSMSGBOXES
          if ($LASTEXITCODE -ne 0) { throw "silent install failed with $LASTEXITCODE" }
          foreach ($p in @('src\Slop.ps1','run.vbs','tools\slop-fetch-assets.ps1',
                           'runtime\models\Qwen3.5-2B-Q4_K_M.gguf',
                           'runtime\whisper\models\ggml-small.bin','data','.sloppy-install.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dir $p))) { throw "missing after install: $p" }
          }
          $link = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Sloppy\Sloppy.lnk'
          if (-not (Test-Path -LiteralPath $link)) { throw 'Start Menu shortcut missing' }

      - name: Ensure the release exists
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release view "${{ github.ref_name }}" 2>$null
          if ($LASTEXITCODE -ne 0) {
            gh release create "${{ github.ref_name }}" --generate-notes --title "Sloppy ${{ github.ref_name }}"
          }

      - name: Upload release assets
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release upload "${{ github.ref_name }}" `
            artifacts/SloppySetup.exe `
            runtime/models/Qwen3.5-2B-Q4_K_M.gguf `
            runtime/whisper/models/ggml-small.bin `
            SHA256SUMS.txt --clobber
```

- [ ] **Step 4: Confirm GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-installer-check.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml tests/slop-installer-check.ps1
git commit -m "feat: publish single-folder installer from release tags"
```

The release assets themselves are uploaded only by GitHub Actions on a tag. Do not create a tag, push, or publish a release in this change stream without explicit user approval. Until that release exists, a real end-to-end install will stop at the model download with an explicit message — this is the expected, honest state.

---

### Task 10: Docs, tour anchors and final gates

**Files:**
- Modify: `.tours/architect-slop-architecture.tour`
- Modify: `tests/slop-tour-check.ps1`
- Modify: `README.md`
- Test: full CI-equivalent gate

- [ ] **Step 1: Recompute tour anchors after source edits**

Tasks 1–8 changed line counts in `src/Slop.ps1`, `src/Slop.Config.ps1`, `src/Slop.Route.ps1` and `src/Slop.Audio.ps1`. For each step in `.tours/architect-slop-architecture.tour`, find the new line of the fragment asserted in `tests/slop-tour-check.ps1:20-37`:

Run this block directly in the repo's pwsh session (no nested shell):

```powershell
$tour = Get-Content .tours/architect-slop-architecture.tour -Raw | ConvertFrom-Json
$expected = @{
  1='Status: accepted'; 3='Add-Type -AssemblyName PresentationFramework';
  4='function New-SlopMotionState'; 5='function Get-SlopIdleAction';
  6='public sealed class SlopFrame'; 7='void Build()';
  8='function New-SlopFaceLayer'; 9='function New-SlopRequestState';
  10='function Test-SlopOpenCodeConfig'; 11='function Start-Stream';
  12='function Add-SlopApprovalCard'; 13='function Request-StopStream';
  14='function Invoke-SlopSenseScan'; 15='function Expand-Chat';
  16='MotionTimer'; 17='function Apply-SlopMotion'
}
$i = 0
foreach ($s in $tour.steps) {
  $i++
  if (-not $s.file) { continue }
  $lines = @(Get-Content $s.file)
  $want = $expected[$i]
  if (-not $want) { continue }
  $found = 0; $n = 0
  foreach ($l in $lines) { $n++; if ($l -match [regex]::Escape($want)) { $found = $n; break } }
  '{0}: {1} old={2} new={3}' -f $i, $s.file, $s.line, $found
}
```

Update only the `line` values whose fragment moved. If a fragment no longer exists, fix the source or the expected fragment — do not point the tour at a blank line.

- [ ] **Step 2: Confirm tour GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/slop-tour-check.ps1 -Output Detailed"`
Expected: 18 steps, all anchors substantive and matching.

- [ ] **Step 3: Update README**

Replace the install section with:

```markdown
## Install

Double-click `install.cmd`, or run the one-liner:

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
```

- [ ] **Step 4: Run the full CI-equivalent gate**

Run from the repo root (the same command as `.github/workflows/ci.yml`):

```powershell
Import-Module Pester -MinimumVersion 6.0
$paths = Get-ChildItem -Path tests -Filter '*-check.ps1' |
    Where-Object { $_.Name -ne 'slop-opencode-check.ps1' } |
    Select-Object -ExpandProperty FullName
Invoke-Pester -Path $paths -CI -Output Detailed
```

Expected: `Failed: 0` and process exit 0. Current baseline is `584 passed, 0 failed`; the new suites should increase the pass count, never reduce it. Read the full output — do not claim success on a partial count.

- [ ] **Step 5: Run review and diff checks**

```bash
git diff --check
```

Expected: no output. Then run the `review` ritual and read its output.

- [ ] **Step 6: Commit**

```bash
git add .tours/architect-slop-architecture.tour tests/slop-tour-check.ps1 README.md
git commit -m "docs: refresh tour anchors and single-folder install instructions"
```

- [ ] **Step 7: Report and stop for user verification**

Report the exact gate output, the local commits, and that the following remain unverified by the agent: Inno compile (ISCC absent locally), real model download (release `v0.3.0` not yet published), no console flash, visible glass/indigo styling, tier switching in the Brain panel, voice readiness. Ask the user to perform those live checks before any release is cut. Do not push, tag, deploy or change visibility.

---

## Final verification checklist

- [ ] Every fenced `powershell` block parses with `[System.Management.Automation.Language.Parser]::ParseInput` (zero errors).
- [ ] Every source anchor cited above was checked against the working tree before the plan was committed.
- [ ] No `TODO`, `TBD`, `fill in`, `similar to Task`, or `implement later` remains in this plan.
- [ ] `git diff --check` clean after each commit.
- [ ] Canonical gate exits 0 with explicit `Failed: 0` before the plan is declared complete.
- [ ] Working tree clean before presenting the execution gate.

## Known external gates (not solvable in this change stream)

- `ISCC` is not installed locally; installing it needs explicit approval. CI pins `InnoSetup` 6.5.4.
- Release `v0.2.0` contains only `install.cmd`. The installer constants target `v0.3.0`, which must be published by a tag after user approval; until then the download step fails explicitly.
- Live UI verification requires the user present: console suppression, tier/model dropdown behavior, visible styling, and voice readiness.
