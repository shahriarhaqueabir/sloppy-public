# Tier 1 Qwen Brain Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. `subagent-driven-development` is explicitly excluded by the standing no-subagents constraint. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tier 1 local brain with Qwen3.5-2B Q4_K_M and track its GGUF with Git LFS while leaving WPF motion, voice, and Tier 2 behavior unchanged.

**Architecture:** Config defaults and the local-model runtime switch from the ignored 3.3 GB Gemma GGUF plus mandatory mmproj to the 1.3 GB text-only Qwen GGUF with optional mmproj and `--jinja`; route and UI labels, preflight, docs, and tests follow the same contract.

**Tech Stack:** PowerShell 7.6, WPF/PowerShell app, llama.cpp b12676 (`llama-server.exe`), Pester 6, Git LFS.

Date: 2026-11-25  
Spec: `docs/plans/2026-11-25-tier1-qwen-brain-switch-design.md`  
Branch: `main`, local commits only. **No push, deploy, or remote change.**

---

## Scope check

This is one subsystem: the Tier 1 local text brain and its supply path. Voice, WPF motion, Tier 2 routing, permissions, and disclosure policy are explicitly out of scope per the approved spec. No separate plans needed.

## File structure

| File | Why |
|---|---|
| `src/Slop.Config.ps1` | Default model name/path/mmproj fields |
| `src/Slop.LocalModel.ps1` | Path resolution, validation, llama-server arguments |
| `src/Slop.ps1` | Static XAML badge and runtime badge fallback strings |
| `tools/slop-preflight.ps1` | Artifact label and optional mmproj check |
| `tools/verify-motion.ps1` | Stand-in paths for live text smoke |
| `tests/slop-config-check.ps1` | Config defaults contract |
| `tests/slop-localmodel-check.ps1` | Runtime path/argument contract |
| `tests/slop-route-check.ps1` | Route badge and plan contract |
| `tests/slop-shell-check.ps1` | First-frame badge and README/architecture static claims |
| `tests/slop-preflight-check.ps1` | Preflight label and stub paths |
| `README.md`, `docs/architecture.md`, `docs/bundling-and-first-run-plan.md`, `docs/third-party-notices.md`, `docs/release-readiness.md` | Honest user-facing wording and provenance |
| `.gitignore` | Remove the Gemma-specific GGUF ignore |
| `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` | LFS-tracked Tier 1 artifact (supply prerequisite) |
| `.tours/architect-slop-architecture.tour` | Only if a source line shift stales an anchor |

Not touched: `src/Slop.Adapter.OpenAi.ps1`, `src/Slop.Lifecycle.ps1`, `src/Slop.Provider.ps1`, `src/Slop.Audio.ps1`, `src/Slop.Motion.ps1`, `src/Slop.Frame.ps1`, `src/Slop.Face.ps1`, Tier 2 files, private PSloppy, `docs/research/*.md`. The research files inventory external CLIs/models and contain no Tier 1 brain or supply claim; Qwen provenance goes into `docs/third-party-notices.md` and the release-readiness recon note instead.

## Global constraints for the executor

- RED first. Every source change below has a test that fails before it and passes after it.
- Commit only explicit paths. Never `git add -A`. Never include `security-scan-results.json` or `.memory/`.
- In `src/Slop.ps1`, replace strings **in place**. Do not add or remove lines above tour anchors unless you refresh the tour in the same pass.
- Use single-quoted PowerShell regexes. Double-quoted regexes containing `$` will interpolate and silently fail.
- Do not reuse `$args` as a local variable name; it is an automatic variable.
- Canonical gate is `$HOME/.agents/scripts/verify.ps1`. This repo has no `verify.ps1` of its own.

---

### Task 1: RED — update the five test suites to the Qwen contract

**Files:** the five `tests/*.ps1` files listed in the file structure.

No source changes in this task. At the end, all five suites must fail for the intended reasons.

- [ ] **Step 1.1: config contract**

Replace the Gemma defaults test in `tests/slop-config-check.ps1` (currently lines 39–47) with:

```powershell
    It 'defaults local bundled context and readiness for Qwen3.5-2B' {
        $cfg = New-SlopDefaultConfig
        $cfg.localModelName | Should -Be 'Qwen3.5-2B Q4_K_M'
        $cfg.localModelFile | Should -Match 'Qwen3\.5-2B-Q4_K_M\.gguf$'
        $cfg.localMmprojFile | Should -Be ''
        $cfg.localContextSize | Should -Be 8192
        $cfg.localVisionReady | Should -BeTrue
        $cfg.localAudioReady | Should -BeTrue
    }

    It 'accepts an empty or configured localMmprojFile as valid config' {
        $cfg = New-SlopDefaultConfig
        $cfg.localMmprojFile = ''
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
        $cfg.localMmprojFile = 'models\custom-mmproj.gguf'
        (Test-SlopConfig -Config $cfg).Ok | Should -BeTrue
    }
```

`localVisionReady` and `localAudioReady` stay `$true`: they are unused readiness hooks, not capability claims, and changing them is outside the approved spec.

- [ ] **Step 1.2: runtime path and argument contract**

In `tests/slop-localmodel-check.ps1`:

Replace the first test (currently lines 18–26) with:

```powershell
    It 'resolves Qwen runtime paths under a supplied install root' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $paths.InstallRoot | Should -Be $script:TestRoot
        $paths.ServerExe | Should -Match 'runtime\\llama-b12676-bin-win-cuda-13\.5-x64\\llama-server\.exe$'
        $paths.ModelFile | Should -Match 'models\\Qwen3\.5-2B-Q4_K_M\.gguf$'
        $paths.MmprojFile | Should -Be ''
        $paths.Port | Should -Be 18080
        $paths.BaseUrl | Should -Be 'http://127.0.0.1:18080'
    }
```

Replace the missing-artifact test (currently lines 34–59) with:

```powershell
    It 'requires server and model, treats empty mmproj as optional, and checks a configured mmproj' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $r = Test-SlopLocalModelPaths -Paths $paths
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'llama-server'
        $r.Reason | Should -Match 'model file'
        $r.Reason | Should -Not -Match 'mmproj'

        New-Item -ItemType File -Path $paths.ServerExe -Force | Out-Null
        New-Item -ItemType File -Path $paths.ModelFile -Force | Out-Null
        $r2 = Test-SlopLocalModelPaths -Paths $paths
        $r2.Ok | Should -BeTrue

        $paths.MmprojFile = Join-Path $script:TestRoot 'models\missing-mmproj.gguf'
        $r3 = Test-SlopLocalModelPaths -Paths $paths
        $r3.Ok | Should -BeFalse
        $r3.Reason | Should -Match 'mmproj'

        $paths.Port = 80
        $r4 = Test-SlopLocalModelPaths -Paths $paths
        $r4.Ok | Should -BeFalse
        $r4.Reason | Should -Match 'port'
    }
```

Replace the argument test (currently lines 61–81) with:

```powershell
    It 'builds llama arguments with --jinja, no default mmproj, allowed context size, and clamped threads' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot
        $llamaArgs = @(New-SlopLlamaArguments -Paths $paths -Threads 99 -ContextSize 16384)
        $llamaArgs | Should -Contain '--model'
        $llamaArgs | Should -Contain $paths.ModelFile
        $llamaArgs | Should -Not -Contain '--mmproj'
        $llamaArgs | Should -Contain '--jinja'
        $llamaArgs | Should -Contain '--ctx-size'
        $llamaArgs | Should -Contain '16384'
        $llamaArgs | Should -Contain '--cache-ram'
        $llamaArgs | Should -Contain '0'
        $llamaArgs | Should -Contain '--host'
        $llamaArgs | Should -Contain '127.0.0.1'
        $llamaArgs | Should -Contain '--port'
        $llamaArgs | Should -Contain '18080'
        $llamaArgs | Should -Contain '--alias'
        $llamaArgs | Should -Contain 'sloppy'
        $idx = [array]::IndexOf($llamaArgs, '--threads')
        [int]$llamaArgs[$idx + 1] | Should -BeLessOrEqual 8
        [int]$llamaArgs[$idx + 1] | Should -BeGreaterOrEqual 2
    }

    It 'adds --mmproj only when a projector path is configured' {
        $paths = Get-SlopRuntimePaths -InstallRoot $script:TestRoot -MmprojFile 'models\custom-mmproj.gguf'
        $llamaArgs = @(New-SlopLlamaArguments -Paths $paths)
        $llamaArgs | Should -Contain '--mmproj'
        $llamaArgs | Should -Contain $paths.MmprojFile
        $llamaArgs | Should -Contain '--jinja'
    }
```

In the `passes context size through Start-SlopLocalModel argument construction` test near the end of the file, **delete** this line wherever it appears in that test (line numbers shift after the replacements above):

```powershell
        New-Item -ItemType File -Path $paths.MmprojFile -Force | Out-Null
```

The default `MmprojFile` is now an empty string, so `New-Item` throws `Cannot bind argument to parameter 'Path' because it is an empty string`. Keep the two source-contract assertions in that test unchanged — they guard context-size wiring, not the model name. This is the one existing test that must change beyond the named blocks above; a temp probe caught it before the plan was committed.

- [ ] **Step 1.3: route contract**

In `tests/slop-route-check.ps1`:

- Line 42: change the arbitrary pass-through model string from `'Gemma 4 E2B QAT Q4_0'` to `'Qwen3.5-2B Q4_K_M'`. Expected badge becomes `'Remote · OpenCode Go · Qwen3.5-2B Q4_K_M'`.
- Replace the local-bundled test (lines 73–102) with:

```powershell
    It 'plans a local-bundled route with the Qwen contract when runtime files exist' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('slop-route-rt-' + [guid]::NewGuid().ToString('N'))
        $savedLocal = $env:LOCALAPPDATA
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $env:LOCALAPPDATA = $root
            $paths = Get-SlopRuntimePaths
            New-Item -ItemType File -Path $paths.ServerExe -Force | Out-Null
            New-Item -ItemType File -Path $paths.ModelFile -Force | Out-Null

            $plan = Get-SlopRoutePlan -Config @{
                brain='builtin'; localContextSize=16384; localModelName='Qwen3.5-2B Q4_K_M'
            } -UserText 'hello' -ScriptRootPath 'C:/fake/src' -RepoRootPath 'C:/fake'

            $plan.Ok | Should -BeTrue
            $plan.Kind | Should -Be 'builtin'
            $plan.RouteKind | Should -Be 'local-bundled'
            $plan.ReadyToSend | Should -BeFalse
            $plan.NeedsLocalModelStart | Should -BeTrue
            $plan.Badge | Should -Be 'Local · bundled · Qwen3.5-2B Q4_K_M'
            $plan.AdapterPath | Should -Match 'Slop\.Adapter\.OpenAi\.ps1$'
            $plan.AdapterArgs.BaseUrl | Should -Be 'http://127.0.0.1:18080'
            $plan.LocalModelContextSize | Should -Be 16384
            $plan.LocalModelPaths.MmprojFile | Should -Be ''
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
```

This deliberately stops creating an mmproj stub. If the old mandatory-mmproj wiring is still present, `Get-SlopRoutePlan` fails and the test goes RED for the right reason.

- [ ] **Step 1.4: shell/XAML and doc claims**

In `tests/slop-shell-check.ps1`:

- Line 24: change the regex to `'Qwen3\.5-2B Q4_K_M'`.
- After line 191, add these static assertions (the variables `$gitattributes`, `$readme`, and `$architecture` are already in scope):

```powershell
Assert-True ($readme -match 'Qwen3\.5-2B Q4_K_M') 'README names the Qwen Tier 1 brain'
Assert-True ($architecture -match 'Qwen3\.5-2B Q4_K_M') 'architecture names the Qwen Tier 1 brain'
Assert-True ($gitattributes -match 'runtime/\*\*/\*\.gguf filter=lfs') 'GGUF artifacts are tracked with Git LFS'
```

Keep the existing `'opt-in push-to-talk audio is transcribed locally'` and `'bundled Whisper small'` assertions byte-for-byte; they are honest and still true.

- [ ] **Step 1.5: preflight stub**

In `tests/slop-preflight-check.ps1`, change line 16 to:

```powershell
        Set-Content -LiteralPath (Join-Path $script:Root 'models\Qwen3.5-2B-Q4_K_M.gguf') -Value 'stub' -Encoding ascii
```

In the first test (lines 29–35), add:

```powershell
        ($report.Lines -join "`n") | Should -Match '\[OK\] Qwen model'
```

- [ ] **Step 1.6: prove RED**

```powershell
$suites = @(
    'tests/slop-config-check.ps1',
    'tests/slop-localmodel-check.ps1',
    'tests/slop-route-check.ps1',
    'tests/slop-shell-check.ps1',
    'tests/slop-preflight-check.ps1'
)
foreach ($suite in $suites) {
    "=== $suite ==="
    Invoke-Pester -Path $suite -Output Detailed
}
```

Expected: failures in config defaults, runtime defaults/mmproj/args, route badge/mmproj, first-frame badge + README/architecture, and preflight label. If a suite passes unchanged, its assertion is too weak — strengthen it before continuing.

- [ ] **Step 1.7: commit RED**

```powershell
git add -- tests/slop-config-check.ps1 tests/slop-localmodel-check.ps1 tests/slop-route-check.ps1 tests/slop-shell-check.ps1 tests/slop-preflight-check.ps1
git commit -m "test: red contracts for Tier 1 Qwen brain switch"
```

---

### Task 2: GREEN — config defaults and runtime arguments

**Files:** `src/Slop.Config.ps1`, `src/Slop.LocalModel.ps1`.

- [ ] **Step 2.1: config defaults**

In `src/Slop.Config.ps1`, replace the block at lines 64–72 with:

```powershell
        # Tier 1 bundled local brain (Qwen3.5-2B Q4_K_M). localVisionReady and
        # localAudioReady remain readiness hooks; Tier 1 voice uses the explicit
        # Slop.Audio.ps1 paths below, not a capability flag. localMmprojFile is
        # empty on the default text-only path and is only checked when supplied.
        localModelName    = 'Qwen3.5-2B Q4_K_M'
        localModelFile    = 'models\Qwen3.5-2B-Q4_K_M.gguf'
        localMmprojFile   = ''
        localContextSize  = 8192
        localVisionReady  = $true
        localAudioReady   = $true
```

No validator or backfill change: `localMmprojFile` already allows an empty string because it is not a mandatory parameter anywhere in `Test-SlopConfig` or `Read-SlopConfig`. The existing backfill lines 197–199 already treat whitespace-only as "use default", and the new default is empty — that behavior is unchanged.

- [ ] **Step 2.2: bundled name and runtime paths**

In `src/Slop.LocalModel.ps1`, replace line 14 with:

```powershell
function Get-SlopBundledModelName { return 'Qwen3.5-2B Q4_K_M' }
```

Replace `Get-SlopRuntimePaths` (lines 27–41) with:

```powershell
function Get-SlopRuntimePaths {
    param(
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Sloppy'),
        [AllowEmptyString()][string]$ModelFile = 'models\Qwen3.5-2B-Q4_K_M.gguf',
        [AllowEmptyString()][string]$MmprojFile = ''
    )
    $resolvedMmproj = ''
    if (-not [string]::IsNullOrWhiteSpace($MmprojFile)) {
        # File is non-empty here, so Resolve-SlopRuntimeFilePath never falls back
        # to DefaultRelativePath; passing the same value keeps the mandatory
        # parameter satisfied without allowing an empty mandatory string.
        $resolvedMmproj = Resolve-SlopRuntimeFilePath -InstallRoot $InstallRoot -File $MmprojFile -DefaultRelativePath $MmprojFile
    }
    return @{
        InstallRoot = $InstallRoot
        ServerExe   = (Join-Path $InstallRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe')
        ModelFile   = (Resolve-SlopRuntimeFilePath -InstallRoot $InstallRoot -File $ModelFile -DefaultRelativePath 'models\Qwen3.5-2B-Q4_K_M.gguf')
        MmprojFile  = $resolvedMmproj
        Port        = $script:SlopModelPort
        BaseUrl     = "http://127.0.0.1:$script:SlopModelPort"
    }
}
```

- [ ] **Step 2.3: optional mmproj validation**

Replace `Test-SlopLocalModelPaths` (lines 43–51) with:

```powershell
function Test-SlopLocalModelPaths {
    param([Parameter(Mandatory)][hashtable]$Paths)
    $errors = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Paths.ServerExe)) { $errors.Add('the built-in brain is missing llama-server.exe') }
    if (-not (Test-Path -LiteralPath $Paths.ModelFile)) { $errors.Add('the built-in brain model file is missing') }
    if (-not [string]::IsNullOrWhiteSpace([string]$Paths.MmprojFile) -and
        -not (Test-Path -LiteralPath $Paths.MmprojFile)) {
        $errors.Add('the built-in brain mmproj file is missing')
    }
    if ($Paths.Port -lt 1024 -or $Paths.Port -gt 65535) { $errors.Add('the local model port is invalid') }
    return @{ Ok = ($errors.Count -eq 0); Reason = ($errors -join '; ') }
}
```

- [ ] **Step 2.4: arguments with `--jinja`**

Replace `New-SlopLlamaArguments` (lines 53–74) with:

```powershell
function New-SlopLlamaArguments {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [int]$Threads = 0,
        [int]$ContextSize = 8192,
        [int]$MaxTokens = 512
    )
    if ($Threads -le 0) { $Threads = [Environment]::ProcessorCount - 2 }
    $Threads = [Math]::Max(2, [Math]::Min(8, $Threads))
    $ContextSize = Resolve-SlopLocalContextSize -ContextSize $ContextSize
    $llamaArgs = [Collections.Generic.List[string]]::new()
    $llamaArgs.Add('--model')
    $llamaArgs.Add([string]$Paths.ModelFile)
    if (-not [string]::IsNullOrWhiteSpace([string]$Paths.MmprojFile)) {
        $llamaArgs.Add('--mmproj')
        $llamaArgs.Add([string]$Paths.MmprojFile)
    }
    $llamaArgs.Add('--jinja')
    $llamaArgs.Add('--host')
    $llamaArgs.Add('127.0.0.1')
    $llamaArgs.Add('--port')
    $llamaArgs.Add([string]$Paths.Port)
    $llamaArgs.Add('--ctx-size')
    $llamaArgs.Add([string]$ContextSize)
    $llamaArgs.Add('--cache-ram')
    $llamaArgs.Add('0')
    $llamaArgs.Add('--threads')
    $llamaArgs.Add([string]$Threads)
    $llamaArgs.Add('--n-predict')
    $llamaArgs.Add([string]$MaxTokens)
    $llamaArgs.Add('--alias')
    $llamaArgs.Add('sloppy')
    return $llamaArgs.ToArray()
}
```

`--jinja` is unconditional on the local path. The default context sizes stay `8192`, `16384`, `32768`; Qwen's 262K native window is deliberately not exposed.

- [ ] **Step 2.5: prove GREEN and commit**

```powershell
Invoke-Pester -Path tests/slop-config-check.ps1 -Output Detailed
Invoke-Pester -Path tests/slop-localmodel-check.ps1 -Output Detailed
```

The route suite stays RED on the badge string until Step 3.1 changes `src/Slop.ps1`; do not run it as a Task 2 gate. Its runtime-path assertions are already covered by the localmodel suite above, and the full route contract is proven in Step 3.4.

```powershell
git add -- src/Slop.Config.ps1 src/Slop.LocalModel.ps1
git commit -m "feat: default Tier 1 to Qwen with optional mmproj and jinja"
```

---

### Task 3: GREEN — labels, preflight, and the live stand-in harness

**Files:** `src/Slop.ps1`, `tools/slop-preflight.ps1`, `tools/verify-motion.ps1`.

- [ ] **Step 3.1: badge strings (in-place replacements only)**

In `src/Slop.ps1`:

- Line 102: `Text="Local · bundled · Gemma 4 E2B QAT Q4_0"` → `Text="Local · bundled · Qwen3.5-2B Q4_K_M"`
- Line 103: `AutomationProperties.Name="Local · bundled · Gemma 4 E2B QAT Q4_0"` → `AutomationProperties.Name="Local · bundled · Qwen3.5-2B Q4_K_M"`
- Line 1032: `else { 'Gemma 4 E2B QAT Q4_0' }` → `else { 'Qwen3.5-2B Q4_K_M' }`

These are string-only edits. Line counts must not change. Verify with:

```powershell
$before = (Get-Content src/Slop.ps1).Count
$after = (Get-Content src/Slop.ps1).Count
"before=$before after=$after"
```

Expected: `before=after`. If they differ, you added/removed a line; undo and redo as pure replacements.

- [ ] **Step 3.2: preflight label and optional mmproj**

In `tools/slop-preflight.ps1`, replace lines 42–52 with:

```powershell
    $modelPaths = Get-SlopRuntimePaths -InstallRoot $root -ModelFile ([string]$cfg.localModelFile) -MmprojFile ([string]$cfg.localMmprojFile)
    $artifacts = @(
        @{ Label = 'llama server'; Path = $modelPaths.ServerExe },
        @{ Label = 'Qwen model'; Path = $modelPaths.ModelFile }
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$modelPaths.MmprojFile)) {
        $artifacts += @{ Label = 'mmproj'; Path = $modelPaths.MmprojFile }
    }
    foreach ($entry in $artifacts) {
        if (Test-Path -LiteralPath $entry.Path -PathType Leaf) { $lines.Add("[OK] $($entry.Label): $($entry.Path)") }
        else {
            $errors.Add("$($entry.Label) is missing: $($entry.Path)")
            $lines.Add("[FAIL] $($entry.Label): $($entry.Path)")
        }
    }
```

- [ ] **Step 3.3: live stand-in harness**

In `tools/verify-motion.ps1`, replace lines 252–287 with:

```powershell
$script:OriginalLocalAppData = $env:LOCALAPPDATA
$script:StandInModelPath = $null
$script:StandInMmprojPath = $null
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Sloppy'
$bundledServer = Join-Path $installRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe'
$bundledModel = Join-Path $installRoot 'models\Qwen3.5-2B-Q4_K_M.gguf'
if (-not (Test-Path -LiteralPath $bundledServer) -or
    -not (Test-Path -LiteralPath $bundledModel)) {
    $runtimeBin = $env:SLOP_LIVE_RUNTIME_DIR
    $modelFile = $env:SLOP_LIVE_MODEL_FILE
    $mmprojFile = $env:SLOP_LIVE_MMPROJ_FILE
    if ([string]::IsNullOrWhiteSpace($runtimeBin) -or -not (Test-Path -LiteralPath (Join-Path $runtimeBin 'llama-server.exe'))) {
        throw 'bundled brain is not installed; set SLOP_LIVE_RUNTIME_DIR to a llama.cpp bin folder'
    }
    if ([string]::IsNullOrWhiteSpace($modelFile) -or -not (Test-Path -LiteralPath $modelFile)) {
        throw 'bundled brain is not installed; set SLOP_LIVE_MODEL_FILE to a Qwen chat-capable GGUF'
    }
    if (-not [string]::IsNullOrWhiteSpace($mmprojFile) -and -not (Test-Path -LiteralPath $mmprojFile)) {
        throw 'SLOP_LIVE_MMPROJ_FILE points to a missing file'
    }
    $runtimeEnv = Join-Path $dir 'runtime-env'
    Remove-Item $runtimeEnv -Recurse -Force -ErrorAction SilentlyContinue
    $standInRoot = Join-Path $runtimeEnv 'Programs\Sloppy'
    $standInRuntime = Join-Path $standInRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $standInRuntime) | Out-Null
    New-Item -ItemType Junction -Path $standInRuntime -Target $runtimeBin -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $standInRoot 'models') | Out-Null
    $script:StandInModelPath = Join-Path $standInRoot 'models\Qwen3.5-2B-Q4_K_M.gguf'
    New-Item -ItemType SymbolicLink -Path $script:StandInModelPath -Target $modelFile -ErrorAction Stop | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($mmprojFile)) {
        $script:StandInMmprojPath = Join-Path $standInRoot 'models\Qwen3.5-2B-mmproj.gguf'
        New-Item -ItemType SymbolicLink -Path $script:StandInMmprojPath -Target $mmprojFile -ErrorAction Stop | Out-Null
    }
    $env:LOCALAPPDATA = $runtimeEnv
    "STANDIN runtime=$runtimeBin model=$modelFile mmproj=$mmprojFile"
}
```

The teardown block (lines ~538–554) stays as-is: it kills only the stand-in model process matched by `$script:StandInModelPath`. Do not widen that filter.

- [ ] **Step 3.4: prove label GREEN and commit**

```powershell
Invoke-Pester -Path tests/slop-route-check.ps1 -Output Detailed
Invoke-Pester -Path tests/slop-shell-check.ps1 -Output Detailed
Invoke-Pester -Path tests/slop-preflight-check.ps1 -Output Detailed
```

Route and preflight must pass. `slop-shell-check.ps1` still has RED doc assertions from Step 1.4 (README and architecture name); the LFS-rule assertion should already pass. Confirm those two doc assertions are the only remaining failures; the first-frame badge check must pass. Then commit only the source/tool files:

```powershell
git add -- src/Slop.ps1 tools/slop-preflight.ps1 tools/verify-motion.ps1
git commit -m "feat: Qwen labels, optional preflight mmproj, text-only stand-in"
```

---

### Task 4: GREEN — docs, notices, and ignore rule

**Files:** `README.md`, `docs/architecture.md`, `docs/bundling-and-first-run-plan.md`, `docs/third-party-notices.md`, `docs/release-readiness.md`, `.gitignore`.  
Local-only, never committed: `.git/info/exclude` (keeps the old Gemma blob ignored after the tracked ignore rule is removed).

- [ ] **Step 4.1: README**

- Line 13, replace the Gemma sentence with:

  ```text
  Sloppy's Tier 1 path runs **Qwen3.5-2B Q4_K_M** on `llama.cpp` b12676 with the GGUF and runtime tracked via Git LFS; the model is 1.3 GB, under GitHub's 2 GB per-file limit.
  ```

- Line 28 diagram node: `  Route -->|Tier 1 local| Llama[llama.cpp + Qwen GGUF]`
- Line 66 table row: `| Tier 1 | llama.cpp + Qwen3.5-2B Q4_K_M GGUF | Local/default path (LFS-tracked GGUF) |`

- Line 90 bullet:

  ```text
  - For Tier 1: `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` is tracked via Git LFS (1.3 GB) and fetched on checkout; no manual model supply step
  ```

- Line 94, replace with (keep the exact phrase `opt-in push-to-talk audio is transcribed locally`):

  ```text
  Sloppy prefers whatever OpenCode config you already have. If there is none, it installs a minimal zero-trust config; it never overwrites an active one. The Qwen3.5-2B brain answers text locally from the LFS-tracked GGUF under `runtime/models/`, and opt-in push-to-talk audio is transcribed locally by the bundled Whisper small setup before being sent through the same text path. The Whisper CLI and DLLs are bundled; `ggml-small.bin` is downloaded and checksum-verified during setup. Nothing is uploaded for Tier 1. Image capture and `mmproj` remain unused readiness hooks; there are no spoken replies.
  ```

Do not add image, audio-input-to-model, VAD, TTS, or thinking-mode claims.

- [ ] **Step 4.2: architecture**

- Line 109: `        ├─ local (Tier 1) ── llama.cpp b12676 ── Qwen3.5-2B Q4_K_M (LFS-tracked GGUF)`
- Line 110: `        │   localhost:18080, model + optional mmproj, ctx 8192/16384/32768`
- Line 123, replace the paragraph with:

  ```text
  Tier 1 runs locally through `runtime/llama-b12676-bin-win-cuda-13.5-x64/llama-server.exe` and the LFS-tracked `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` (1.3 GB, Apache-2.0); `--jinja` uses the GGUF's embedded chat template. An mmproj is optional and unused by default. HF download cache under `runtime/models/.cache/` is ignored. Text requests use the existing llama.cpp adapter. Opt-in voice input records a short WAV with WinMM; the Whisper CLI and DLLs are bundled under `runtime/whisper/`. `ggml-small.bin` is downloaded and checksum-verified during setup, so the bundled Whisper small setup is complete. `src/Slop.Audio.ps1` transcribes locally and sends the transcript through the same text path. No audio leaves the machine, and there is no TTS or VAD. `mmproj` and `localVisionReady` stay unused readiness hooks; Tier 1 makes no image claim.
  ```

The exact phrase `bundled Whisper small` is asserted by `tests/slop-shell-check.ps1`; keep it.

- [ ] **Step 4.3: bundling plan**

Replace rows and notes that name Gemma:

```markdown
| `runtime/models/Qwen3.5-2B-Q4_K_M.gguf` | ~1.3 GB | Tier 1 local text | LFS-tracked default component. |
| `runtime/models/Qwen3.5-2B-mmproj.gguf` | — | Future multimodal image/audio | Optional, not bundled; no download until multimodal is live-verified. |
```

Then update the remaining Gemma lines:
- line 62: `local chat with bundled Qwen, visible state/motion, local-first privacy, basic controls`
- line 71: `Qwen GGUF present, checksum ok, loads`
- line 156:

  ```text
  | `model-qwen3-5-2b-q4km` | Tier 1 default | ~1.3 GB | LFS-tracked; verify checksum and license notice. |
  ```

- line 157:

  ```text
  | `model-qwen3-5-2b-mmproj` | Optional, feature-gated | — | Only when multimodal is wired, verified, and user opts in. |
  ```
- line 178: `qwen3-5-2b\       # model; optional mmproj not present by default`
- line 250: `Trim llama runtime to minimal server-required files per backend; keep Qwen3.5-2B mmproj feature-gated until verified end-to-end.`

Leave the Tier 2 sections unchanged.

- [ ] **Step 4.4: third-party notices**

Append to `docs/third-party-notices.md`:

```markdown
## Qwen3.5-2B Q4_K_M

- Base model: https://huggingface.co/Qwen/Qwen3.5-2B
- GGUF quant: https://huggingface.co/axteam/Qwen3.5-2B-GGUF (`Qwen3.5-2B-Q4_K_M.gguf`)
- License: Apache-2.0 (base model); the GGUF is a derivative distributed under the same license
- Used for: Tier 1 local text replies through bundled `llama.cpp` b12676 with `--jinja`
```

Do not claim the license review is complete; the existing file already says release-time license review is a separate gate.

- [ ] **Step 4.5: release-readiness recon note**

In `docs/release-readiness.md`:

- Line 15: replace the branch value with `main`, leaving the `- **Branch:**` label intact.
- Line 99: `**Recon note:** Qwen3.5-2B Q4_K_M is Apache-2.0 (base model; GGUF derivative under the same terms); llama.cpp MIT; LLVM OpenMP notice present; CUDA runtime redistribution terms UNVERIFIED.`

Do not mark the license review complete; keep the existing UNVERIFIED CUDA note.

- [ ] **Step 4.6: .gitignore**

Remove exactly these two lines from `.gitignore` (lines 32–33):

```gitignore
# 3.3 GB GGUF exceeds GitHub LFS's 2 GB per-file limit; supply it locally
runtime/models/gemma-4-E2B_q4_0-it.gguf
```

Keep the surrounding cache rules unchanged. The old 3.3 GB Gemma blob is present in this checkout (`runtime/models/gemma-4-E2B_q4_0-it.gguf`); removing the tracked ignore rule would make it show as untracked. Do not delete it. Add a local-only exclude so it stays ignored without changing the committed ignore policy:

```powershell
$gemmaFile = 'runtime/models/gemma-4-E2B_q4_0-it.gguf'
$excludeFile = '.git/info/exclude'
if ((Test-Path -LiteralPath $gemmaFile) -and
    -not (Select-String -LiteralPath $excludeFile -Pattern '^runtime/models/gemma-4-E2B_q4_0-it\.gguf$' -Quiet)) {
    Add-Content -LiteralPath $excludeFile -Value $gemmaFile -Encoding utf8
}
git check-ignore -v $gemmaFile
git check-ignore -v runtime/models/Qwen3.5-2B-Q4_K_M.gguf
```

Expected: the first command reports `.git/info/exclude` as the matching source; the second command has no output (exit code 1). If the Qwen GGUF matches any rule, fix `.gitignore` before continuing. Never stage or commit `.git/info/exclude`.

- [ ] **Step 4.7: prove GREEN and commit**

```powershell
Invoke-Pester -Path tests/slop-shell-check.ps1 -Output Detailed
git diff --check
git add -- README.md docs/architecture.md docs/bundling-and-first-run-plan.md docs/third-party-notices.md docs/release-readiness.md .gitignore
git commit -m "docs: describe LFS-tracked Qwen Tier 1 brain"
```

---

### Task 5: LFS-track the Qwen GGUF

**Files:** `runtime/models/Qwen3.5-2B-Q4_K_M.gguf`.

Prerequisite: the 1.3 GB `Qwen3.5-2B-Q4_K_M.gguf` must exist at that path. If it does not, **stop and report** — do not substitute another quant, do not invent a download URL, and do not mark the task done. The user owns artifact supply.

- [ ] **Step 5.1: confirm LFS rule and size**

```powershell
git check-attr filter -- runtime/models/Qwen3.5-2B-Q4_K_M.gguf
Get-Item -LiteralPath runtime/models/Qwen3.5-2B-Q4_K_M.gguf | Select-Object Name, Length
Get-FileHash -LiteralPath runtime/models/Qwen3.5-2B-Q4_K_M.gguf -Algorithm SHA256
```

Expected: `filter: lfs`, size ≈ 1.3 GB (< 2 GB), and a real SHA-256 recorded in the task output.

- [ ] **Step 5.2: stage and verify pointer**

```powershell
git add -- runtime/models/Qwen3.5-2B-Q4_K_M.gguf
git lfs ls-files --size | Select-String 'Qwen3\.5-2B-Q4_K_M'
git show :runtime/models/Qwen3.5-2B-Q4_K_M.gguf
```

Expected: the file appears in `git lfs ls-files` and `git show` prints an LFS pointer (`version https://git-lfs.github.com/spec/v1`), not binary content.

- [ ] **Step 5.3: commit**

```powershell
git commit -m "chore: track Tier 1 Qwen GGUF with Git LFS"
```

No push. `origin/main` stays behind locally until the user approves a push. If present, the 3.3 GB Gemma file stays on disk, locally excluded via `.git/info/exclude`, unstaged, and untouched.

---

### Task 6: Full verification and live text smoke

No source change except a tour refresh if an anchor drifts.

- [ ] **Step 6.1: canonical gates**

```powershell
& "$HOME/.agents/scripts/verify.ps1"
```

Expected exit 0. Read the full output; do not accept a pass count from `-Output None`. If a nested-worktree WPF discovery failure appears, confirm whether it is the known pre-existing one before reporting it.

- [ ] **Step 6.2: tour anchors**

```powershell
Invoke-Pester -Path tests/slop-tour-check.ps1 -Output Detailed
```

`src/Slop.ps1` badge edits are in-place, so anchors should still match. If an anchor drifts, refresh only that `.tours/architect-slop-architecture.tour` line and commit it separately:

```powershell
git add -- .tours/architect-slop-architecture.tour
git commit -m "docs: refresh tour anchors after Qwen badge edit"
```

Do not change step titles or descriptions while refreshing anchors.

- [ ] **Step 6.3: diff hygiene**

```powershell
git diff --check
git status --short --branch
```

Expected: no whitespace errors, no unexpected untracked files, no `security-scan-results.json` in the index.

- [ ] **Step 6.4: live text smoke (acceptance gate)**

Run only with approved artifacts present:

```powershell
if ([string]::IsNullOrWhiteSpace($env:SLOP_LIVE_RUNTIME_DIR) -or
    [string]::IsNullOrWhiteSpace($env:SLOP_LIVE_MODEL_FILE)) {
    throw 'caller must set SLOP_LIVE_RUNTIME_DIR and SLOP_LIVE_MODEL_FILE before this step'
}
Remove-Item Env:SLOP_LIVE_MMPROJ_FILE -ErrorAction SilentlyContinue
& ./tools/verify-motion.ps1
```

Expected: `STANDIN` line names the Qwen model with empty mmproj, the bundled brain starts without `--mmproj`, a text prompt receives a reply, and teardown reports `TEARDOWN complete` with no orphan `llama-server.exe` or `Slop.ps1` process.

If the artifacts are unavailable, stop and report the smoke as **blocked/deferred**. Do not claim live behavior from headless suites and do not claim the acceptance criteria are met. Voice smoke remains deferred unconditionally.

- [ ] **Step 6.5: final report**

Report exact commands and outputs for: focused suites, canonical verify, tour check, diff check, LFS pointer, and live smoke (or its deferral). State explicitly that no push occurred and that WPF motion, voice, and Tier 2 were not changed.

---

## Scaffolding validation performed before this plan was written

- All 33 fenced PowerShell blocks were parsed with `[System.Management.Automation.Language.Parser]::ParseInput`; parse errors: 0.
- The replacement functions and tool wiring were mirrored into a temp copy of `src/` and `tools/` with the RED tests and executed headlessly: config 23/23, localmodel 12/12, route 13/13, preflight 5/5 — 53 passed, 0 failed.
- That probe found one real scaffolding defect: the existing `Start-SlopLocalModel` test created an mmproj stub, which throws once the default mmproj path is empty. The plan now includes the one-line deletion in Task 1.2; after the fix, the probe is green.
- Function names, parameters, and variables were cross-checked against shipped source. `$args` was deliberately avoided as a local variable name; `[Parameter(Mandatory)][string]` empty-string binding was avoided in `Get-SlopRuntimePaths` by resolving mmproj only when non-empty.
- Five high-risk regexes were checked against their own replacement text: config GGUF name, server path, LFS gitattributes, preflight label, and first-frame badge. All matched; patterns are single-quoted with escaped `.` and `*` and no `$` interpolation.
- Tour anchors were checked: none of the edited `src/Slop.ps1` lines (102, 103, 1032) is a tour anchor; anchored steps land at lines 6, 638, 728, 747, 1265, 1411, 1972.
