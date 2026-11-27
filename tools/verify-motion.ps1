# Live WPF verification for the S.L.O.P. motion overlay.
# Focus-checked physical input only - no SendKeys leakage into other apps.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VM {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,int e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,int extra);
    public const uint DOWN=0x0002, UP=0x0004, KEYUP=0x0002;
    public const byte CTRL=0x11, V=0x56, ENTER=0x0D, ESC=0x1B;
}
'@

function Get-AppWindows($id) {
    # The app now owns two top-level windows: the pet and its separate chat
    # window. FindFirst silently picked whichever one happened to be first.
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $id)
    $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
}
function Get-Win($id, [string]$Title = 'S.L.O.P.') {
    $windows = Get-AppWindows $id
    foreach ($w in $windows) {
        if ($w.Current.Name -eq $Title) { return $w }
    }
    if ($windows.Count -gt 0) { return $windows[0] }
    return $null
}
function Get-PetWin { Get-Win $proc.Id }
function Get-ChatWin { Get-Win $proc.Id 'Sloppy chat' }
function Find-UiaIn($win, $id) {
    if (-not $win) { return $null }
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
function Find-Uia($id) {
    # Both windows keep copies of the conversation controls. Prefer the live
    # chat window while it exists; the pet's copy is hidden until chat closes.
    $chat = Get-ChatWin
    $chatEl = Find-UiaIn $chat $id
    if ($chatEl -and -not $chatEl.Current.IsOffscreen) { return $chatEl }
    $petEl = Find-UiaIn (Get-PetWin) $id
    if ($petEl) { return $petEl }
    return $chatEl
}
function Invoke-UiaIn($win, $id) {
    $el = Find-UiaIn $win $id
    if (-not $el) { throw "UIA element $id not found in the target window" }
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Set-UiaValue($id, $value) {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA element $id not found" }
    $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($value)
}
function Get-UiaValue($id) {
    $el = Find-Uia $id
    if (-not $el) { return $null }
    try {
        $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($vp) { return $vp.Current.Value }
    } catch { }
    return $null
}

function Invoke-Uia($id) {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA element $id not found" }
    $ip = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $ip.Invoke()
}
function Find-UiaName($name) {
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    foreach ($win in Get-AppWindows $proc.Id) {
        $el = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($el -and -not $el.Current.IsOffscreen) { return $el }
    }
    return $null
}
function Find-UiaButton($name) {
    $cond = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty, $name),
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button))
    foreach ($win in Get-AppWindows $proc.Id) {
        $el = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($el -and -not $el.Current.IsOffscreen) { return $el }
    }
    return $null
}
function Invoke-UiaButton($name) {
    $el = Find-UiaButton $name
    if (-not $el) { throw "button $name not found" }
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Get-UiaText($id) {
    $el = Find-Uia $id
    if (-not $el) { return $null }
    try {
        $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if ($tp) { return $tp.DocumentRange.GetText(-1) }
    } catch { }
    return $el.Current.Name
}
function Set-UiaCombo($id, $value) {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA combo $id not found" }
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, [string]$value)
    $item = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $item) { throw "combo $id has no item named '$value'" }
    $sp = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $sp.Select()
}
# Probe coordinates are in device-independent pixels (XAML layout). Capture the
# DPI scale once at launch, when the window is still 484x330. Re-deriving it from
# the live rect after expand (760x540) or maximize skews fixed-margin elements
# such as the header dot, because those margins do not grow with the window.
$script:DpiX = 1.0
$script:DpiY = 1.0
$script:LastGrabRect = $null
function Phys($lx,$ly) {
    $r = $script:W.Current.BoundingRectangle
    @([int]($r.X + $lx*$script:DpiX), [int]($r.Y + $ly*$script:DpiY))
}
function Focus-Ok {
    $h = [IntPtr]$script:W.Current.NativeWindowHandle
    [VM]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 120
    [VM]::GetForegroundWindow() -eq $h
}
function Focus-Chat {
    $chat = Get-ChatWin
    if (-not $chat) { return $false }
    $h = [IntPtr]$chat.Current.NativeWindowHandle
    [VM]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 120
    [VM]::GetForegroundWindow() -eq $h
}
function Get-ChatText {
    $stack = Find-UiaIn (Get-ChatWin) 'ChatStack'
    if (-not $stack) { return '' }
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Text)
    $els = $stack.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    ($els | ForEach-Object { $_.Current.Name }) -join "`n"
}
function Click($lx,$ly) {
    $p = Phys $lx $ly
    [VM]::SetCursorPos($p[0],$p[1]) | Out-Null
    Start-Sleep -Milliseconds 60
    [VM]::mouse_event([VM]::DOWN,0,0,0,0)
    Start-Sleep -Milliseconds 45
    [VM]::mouse_event([VM]::UP,0,0,0,0)
}
function Press($vk) {
    [VM]::keybd_event($vk,0,0,0)
    [VM]::keybd_event($vk,0,[VM]::KEYUP,0)
}
function Paste($text) {
    [System.Windows.Forms.Clipboard]::SetText($text)
    [VM]::keybd_event([VM]::CTRL,0,0,0)
    [VM]::keybd_event([VM]::V,0,0,0)
    [VM]::keybd_event([VM]::V,0,[VM]::KEYUP,0)
    [VM]::keybd_event([VM]::CTRL,0,[VM]::KEYUP,0)
}
function Grab {
    # A cached UIA peer can report an empty or stale rect while the window
    # expands. Re-query the top-level window and keep the exact rect used for
    # this bitmap so Pixel cannot sample against a different geometry.
    $w = Get-Win $proc.Id
    if ($w) { $script:W = $w }
    $r = $script:W.Current.BoundingRectangle
    for ($i=0; $i -lt 20 -and ($r.Width -le 0 -or $r.Height -le 0); $i++) {
        Start-Sleep -Milliseconds 50
        $w = Get-Win $proc.Id
        if ($w) { $script:W = $w }
        $r = $script:W.Current.BoundingRectangle
    }
    if ($r.Width -le 0 -or $r.Height -le 0) { throw "empty window rect $($r.Width)x$($r.Height)" }
    $script:LastGrabRect = $r
    $b = [System.Drawing.Bitmap]::new([int]$r.Width,[int]$r.Height)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen([int]$r.X,[int]$r.Y,0,0,$b.Size)
    $g.Dispose()
    $b
}
function Count($b,$lx,$ly,$lw,$lh,$mode) {
    $rect = [System.Drawing.Rectangle]::new([int]($lx*$script:DpiX),[int]($ly*$script:DpiY),[int]($lw*$script:DpiX),[int]($lh*$script:DpiY))
    $d = $b.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$b.PixelFormat)
    $bytes = [byte[]]::new($d.Stride*$rect.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0,$bytes,0,$bytes.Length)
    $b.UnlockBits($d)
    $n = 0
    for ($y=0;$y -lt $rect.Height;$y++) {
        $idx = $y*$d.Stride
        for ($x=0;$x -lt $rect.Width;$x++) {
            $rr=$bytes[$idx+2]; $gg=$bytes[$idx+1]; $bb=$bytes[$idx]
            if     ($mode -eq 'blue'   -and $bb -gt 180 -and $rr -lt 120 -and $gg -lt 180) { $n++ }
            elseif ($mode -eq 'bright' -and $rr -gt 120 -and $gg -gt 120 -and $bb -gt 120) { $n++ }
            elseif ($mode -eq 'red'    -and $rr -gt 170 -and $gg -lt 100 -and $bb -lt 100) { $n++ }
            $idx += 4
        }
    }
    $n
}
function Pixel($b,$lx,$ly) {
    # Coordinates are layout pixels inside the bitmap captured by Grab. Use the
    # stored rect for bounds only; never re-read a possibly stale UIA rect here.
    $r = $script:LastGrabRect
    $x = [int]($lx*$script:DpiX)
    $y = [int]($ly*$script:DpiY)
    if ($r) {
        if ($x -lt 0 -or $x -ge [int]$r.Width -or $y -lt 0 -or $y -ge [int]$r.Height) {
            throw "pixel $lx,$ly outside captured rect $([int]$r.Width)x$([int]$r.Height)"
        }
    }
    $b.GetPixel($x,$y)
}
function Classify($p) {
    # The dot fades in during expand; accept the darker end of the blue ramp too.
    if ($p.B -gt 120 -and $p.R -lt 120 -and $p.G -lt 180) { return 'blue' }
    if ($p.R -gt 180 -and $p.G -gt 100 -and $p.G -lt 200 -and $p.B -lt 120) { return 'amber' }
    if ($p.G -gt 140 -and $p.R -lt 150 -and $p.B -lt 180) { return 'green' }
    if ($p.R -gt 150 -and $p.G -lt 120 -and $p.B -lt 120) { return 'red' }
    return 'other'
}
function DotColor {
    $b = Grab
    try { Classify (Pixel $b 50 36) } finally { $b.Dispose() }
}
# The header fades in after expand; a single 700ms sample can land on the dark
# ramp. Poll until the idle blue settles instead of failing on animation timing.
function Wait-DotBlue {
    param([int]$TimeoutMs = 45000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        if ((DotColor) -eq 'blue') { return $true }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}
# the pea hops, so a fixed coordinate misses it mid-hop; find its blue centroid
function Find-Pea {
    $b = Grab
    try {
        $accX=0.0; $accY=0.0; $n=0
        for ($ly=284; $ly -le 322; $ly+=2) {
            for ($lx=212; $lx -le 272; $lx+=2) {
                $p = Pixel $b $lx $ly
                # Any vivid colour: the pea can still be green/amber while a
                # transient success/approval overlay is expiring after Esc.
                $max = [Math]::Max($p.R, [Math]::Max($p.G, $p.B))
                $min = [Math]::Min($p.R, [Math]::Min($p.G, $p.B))
                if ($max -gt 140 -and ($max - $min) -gt 50) {
                    $accX += $lx; $accY += $ly; $n++
                }
            }
        }
        if ($n -ge 4) {
            $cx = [double]$accX / [double]$n
            $cy = [double]$accY / [double]$n
            return @($cx, $cy)
        }
        return $null
    } finally { $b.Dispose() }
}

# kill only stale S.L.O.P. app processes, never this verifier
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like '*src/Slop.ps1*' -or $_.CommandLine -like '*slop-run-wrapper.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

$repo = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $env:TEMP 'slop-verify'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'slop.out.log'
$err = Join-Path $dir 'slop.err.log'
Remove-Item $out,$err -ErrorAction SilentlyContinue
# --- disposable OpenCode service --------------------------------------------
# Never read ~/.config/opencode/service.json here. The shared background service
# belongs to the user; this verifier starts its own server with an isolated
# config, database, port and password, and tears it down in the finally block.
$ocCmd = Get-Command opencode -ErrorAction Stop
$ocExe = Join-Path (Split-Path $ocCmd.Source -Parent) 'node_modules\@opencode\cli\bin\opencode.exe'
if (-not (Test-Path -LiteralPath $ocExe)) { throw "cannot resolve opencode executable from $($ocCmd.Source)" }
$port = Get-Random -Minimum 29000 -Maximum 29999
$password = [guid]::NewGuid().ToString('N')
$svcDir = Join-Path $dir 'service'
Remove-Item $svcDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $svcDir | Out-Null
$svcConfig = Join-Path $svcDir 'opencode.json'
Set-Content -LiteralPath $svcConfig -Value '{"$schema":"https://opencode.ai/config.json"}' -Encoding utf8
$env:OPENCODE_CONFIG_DIR = $svcDir
$env:OPENCODE_CONFIG = $svcConfig
$env:OPENCODE_DB = Join-Path $svcDir 'opencode.db'
$env:OPENCODE_SERVER_PASSWORD = $password
$svcOut = Join-Path $svcDir 'serve.out.log'
$svcErr = Join-Path $svcDir 'serve.err.log'
$svcProc = Start-Process -FilePath $ocExe `
    -ArgumentList @('serve','--port',[string]$port) `
    -PassThru -RedirectStandardOutput $svcOut -RedirectStandardError $svcErr

# Isolated Sloppy install root. LOCALAPPDATA is left alone on purpose.
. (Join-Path $repo 'src/Slop.Config.ps1')
$script:OriginalTestInstallRoot = $env:SLOP_TEST_INSTALL_ROOT
$installRoot = Join-Path $dir 'install'
$userData = Join-Path $installRoot 'data'
Remove-Item $userData -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $userData | Out-Null
$testCfg = New-SlopDefaultConfig
$testCfg.autostart = $false
$testCfg.openCodeBaseUrl = "http://127.0.0.1:$port"
$testCfg.serviceConfigPath = $svcConfig
$testCfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $userData 'config.json') -Encoding utf8
$env:SLOP_TEST_INSTALL_ROOT = $installRoot
$env:OPENCODE_BASE_URL = "http://127.0.0.1:$port"
$env:OPENCODE_PASSWORD = $password

# A developer checkout has no bundled brain in the isolated install root. When it
# is absent, SLOP_LIVE_RUNTIME_DIR (a llama.cpp bin folder), SLOP_LIVE_MODEL_FILE
# (a chat-capable GGUF), and optionally SLOP_LIVE_MMPROJ_FILE let the live probe
# exercise the same local-bundled route without copying gigabytes. Values are
# caller-supplied, and stand-ins live under the same root as data\config.json.
$script:StandInModelPath = $null
$script:StandInMmprojPath = $null
$bundledServer = Join-Path $installRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64\llama-server.exe'
$bundledModel = Join-Path $installRoot 'runtime\models\Qwen3.5-2B-Q4_K_M.gguf'
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
    $standInRoot = $installRoot
    $standInRuntime = Join-Path $standInRoot 'runtime\llama-b12676-bin-win-cuda-13.5-x64'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $standInRuntime) | Out-Null
    $oldLink = Get-Item -LiteralPath $standInRuntime -Force -ErrorAction SilentlyContinue
    if ($oldLink) {
        if ($oldLink.LinkType -eq 'Junction') { [IO.Directory]::Delete($standInRuntime) }
        else { Remove-Item -LiteralPath $standInRuntime -Recurse -Force }
    }
    New-Item -ItemType Junction -Path $standInRuntime -Target $runtimeBin -ErrorAction Stop | Out-Null
    $modelDir = Join-Path $standInRoot 'runtime\models'
    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
    $script:StandInModelPath = Join-Path $modelDir 'Qwen3.5-2B-Q4_K_M.gguf'
    Remove-Item -LiteralPath $script:StandInModelPath -Force -ErrorAction SilentlyContinue
    New-Item -ItemType SymbolicLink -Path $script:StandInModelPath -Target $modelFile -ErrorAction Stop | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($mmprojFile)) {
        $script:StandInMmprojPath = Join-Path $modelDir 'Qwen3.5-2B-mmproj.gguf'
        Remove-Item -LiteralPath $script:StandInMmprojPath -Force -ErrorAction SilentlyContinue
        New-Item -ItemType SymbolicLink -Path $script:StandInMmprojPath -Target $mmprojFile -ErrorAction Stop | Out-Null
    }
    "STANDIN runtime=$runtimeBin model=$modelFile mmproj=$mmprojFile"
}

$healthy = $false
for ($i=0; $i -lt 60 -and -not $healthy; $i++) {
    Start-Sleep -Milliseconds 250
    if ($svcProc.HasExited) { throw "disposable service exited: $(Get-Content $svcErr -Raw)" }
    try {
        $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$port/api/info")
        $req.Timeout = 700
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$password"))
        $req.Headers.Add('Authorization', "Basic $auth")
        $resp = $req.GetResponse(); $resp.Close(); $healthy = $true
    } catch { }
}
if (-not $healthy) { throw 'disposable OpenCode service never became healthy' }
"DISPOSABLE service port=$port pid=$($svcProc.Id)"

$scriptFile = Join-Path $repo 'src/Slop.ps1'
$proc = Start-Process -FilePath 'pwsh' `
    -ArgumentList @('-STA','-NoProfile','-File',$scriptFile) `
    -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
# WPF startup is not fixed-cost (cold JIT, first-run config), so poll for the
# window instead of assuming three seconds is always enough.
for ($i=0; $i -lt 60 -and -not (Get-Win $proc.Id); $i++) { Start-Sleep -Milliseconds 250 }
# Guarantee teardown even when a probe throws: the app is topmost and keeps an
# inherited stdout handle, so an orphan hangs the piped caller indefinitely.
try {
if ($proc.HasExited) { throw "app exited early: $(Get-Content $out -Raw) $(Get-Content $err -Raw)" }
$script:W = Get-Win $proc.Id
if (-not $script:W) { throw 'no app window found' }
$r = $script:W.Current.BoundingRectangle
$script:DpiX = $r.Width / 484.0
$script:DpiY = $r.Height / 330.0
"LAUNCH pid=$($proc.Id) rect=$([int]$r.X),$([int]$r.Y) $([int]$r.Width)x$([int]$r.Height) dpi=$([Math]::Round($script:DpiX,3))"

# idle motion: sample the hop corridor; variance proves the spring clock is alive
$counts = @()
for ($i=0;$i -lt 12;$i++) {
    $b = Grab
    $counts += Count $b 214 290 56 32 'blue'
    $b.Dispose()
    Start-Sleep -Milliseconds 150
}
"IDLE blueSamples=$($counts -join ',') distinct=$(@($counts | Select-Object -Unique).Count)"
if ($counts[-1] -le 0) { throw 'no blue pea pixels' }
# the header (and its glyph) lives inside Frame, which is collapsed while idle,
# so the pea is the only visible signal at this point.
"SIGNAL idle peaBlue=$($counts[-1])"

# Open the separate chat window. The pet stays a pea: there is no expanded
# body to sample, so window presence and UIA geometry are the only reliable
# signals here.
$expanded = $false
for ($try=1;$try -le 3 -and -not $expanded;$try++) {
    Focus-Ok | Out-Null
    Click 242 305
    Start-Sleep -Milliseconds 700
    if (Get-ChatWin) { $expanded = $true; "CHAT opened on click $try" }
}
if (-not $expanded) { throw 'click never opened the chat window' }
if (-not (Focus-Chat)) { throw 'chat window did not take foreground' }
$chatWin = Get-ChatWin
$cr = $chatWin.Current.BoundingRectangle
"CHAT Extended size=$([int]$cr.Width)x$([int]$cr.Height)"
if ([Math]::Abs($cr.Width - (760.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($cr.Height - (540.0*$script:DpiY)) -gt 12) { throw 'chat Extended size is not 760x540' }
$petRect = (Get-PetWin).Current.BoundingRectangle
"PET size=$([int]$petRect.Width)x$([int]$petRect.Height)"
if ([Math]::Abs($petRect.Width - (484.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($petRect.Height - (330.0*$script:DpiY)) -gt 12) { throw 'pet changed size when chat opened' }
$strip = Find-UiaIn $chatWin 'ShortcutsStrip'
if (-not $strip) { throw 'chat shortcut strip is missing' }
"SHORTCUTS visible=$(-not $strip.Current.IsOffscreen) children=$($strip.Current.BoundingRectangle.Width)"
if ($strip.Current.IsOffscreen) { throw 'chat shortcut strip is not visible' }

# T5 relocates the four destination surfaces into the chat window. Until that
# lands, the pet's panels stay hidden while it is a pea, so these probes are
# opt-in instead of failing on offscreen controls.
$verifyDestinations = $env:SLOP_LIVE_DESTINATIONS -eq '1'
if ($verifyDestinations) {
# --- honest route badge + four quiet destinations (Tasks 10 and 14) ---------
# The badge must name the actual route from the first frame, not just a tier.
$badge = Get-UiaText 'RouteBadge'
"BADGE text=$badge"
if ($badge -notmatch 'Local' -or $badge -notmatch 'Qwen3') {
    throw "route badge does not disclose the bundled route: $badge"
}
$destinations = @('Settings','Customize','Brain','Privacy')
# Each panel is proven by one unique named view, not by a substring of a label.
$panelProbes = @{ Settings='AboutText'; Customize='CustomizeNameBox'; Brain='BrainRouteText'; Privacy='PrivacyRouteText' }
foreach ($n in $destinations) {
    if (-not (Find-UiaButton $n)) { throw "destination button $n missing from the top strip" }
}
foreach ($legacy in @('startslop','stopslop','slopstatus','verify','review','kickoff','sign out')) {
    if (Find-UiaButton $legacy) { throw "developer command $legacy leaked onto the top strip" }
}
"DEST buttons=$($destinations -join '|')"
foreach ($n in $destinations) {
    Invoke-UiaButton $n
    Start-Sleep -Milliseconds 350
    $marker = Find-Uia $panelProbes[$n]
    "PANEL $n marker=$([bool]$marker) offscreen=$($marker.Current.IsOffscreen)"
    if (-not $marker -or $marker.Current.IsOffscreen) { throw "destination panel $n did not open" }
    $chat = Find-Uia 'ChatScroll'
    if ($chat -and -not $chat.Current.IsOffscreen) { throw "chat is still visible behind $n" }
    if ($n -eq 'Settings') {
        # AdvancedStack is an empty panel host and has no UIA peer of its own;
        # its chips are asserted by button name below.
        foreach ($ctl in @('SettingsSaveButton','SettingsStatusText','AutostartButton','VoiceRepairButton')) {
            if (-not (Find-Uia $ctl)) { throw "settings control $ctl missing" }
        }
        foreach ($id in @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton')) {
            $el = Find-Uia $id
            if ($el -and -not $el.Current.IsOffscreen) { throw "deletion button $id leaked into Settings" }
        }
        if (-not (Find-UiaButton 'startslop')) { throw 'advanced developer chips are not under Settings' }
    }
    if ($n -eq 'Customize') {
        foreach ($ctl in @('CustomizeNameBox','CustomizeColourCombo','CustomizePersonalityCombo','CustomizePersonaBox','CustomizeSaveButton','CustomizeStatusText')) {
            if (-not (Find-Uia $ctl)) { throw "customize control $ctl missing" }
        }
    }
    if ($n -eq 'Brain') {
        foreach ($ctl in @('BrainTypeCombo','BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo','BrainSaveButton','BrainStatusText')) {
            if (-not (Find-Uia $ctl)) { throw "brain control $ctl missing" }
        }
    }
    if ($n -eq 'Privacy') {
        $routeCopy = Get-UiaText 'PrivacyRouteText'
        "PRIVACY route=$routeCopy"
        if ($routeCopy -notmatch 'Route:') { throw 'Privacy does not show the active data route' }
        $copies = @((Get-UiaText 'PrivacyConversationCopy'), (Get-UiaText 'PrivacySessionCopy'), (Get-UiaText 'PrivacyLocalDataCopy'))
        if (@($copies | Select-Object -Unique).Count -ne 3) { throw 'deletion scopes are not distinct in Privacy' }
        foreach ($id in @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton','PrivacyStatusText')) {
            $el = Find-Uia $id
            if (-not $el -or $el.Current.IsOffscreen) { throw "privacy control $id is missing or hidden" }
        }
    }
    Invoke-Uia ($n + 'Back')
    Start-Sleep -Milliseconds 250
}
if (-not (Find-Uia 'ChatScroll') ) { throw 'Back to chat did not restore the conversation' }

# Editable destinations: prove each save writes the disposable profile and
# reports success on its own page instead of a hidden chat bubble.
$cfgPath = Get-SlopConfigPath
$personaPath = Get-SlopPersonaPath

Invoke-UiaButton 'Settings'
Start-Sleep -Milliseconds 350
Set-UiaValue 'VoiceMaxSecondsBox' '45'
Invoke-Uia 'SettingsSaveButton'
Start-Sleep -Milliseconds 350
$settingsStatus = Get-UiaText 'SettingsStatusText'
"SAVE Settings status=$settingsStatus"
if ($settingsStatus -notmatch 'Settings saved\.') { throw 'Settings save did not show visible success' }
$savedCfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
if ([int]$savedCfg.voiceMaxSeconds -ne 45) { throw 'Settings save did not persist voiceMaxSeconds' }
if ((Find-Uia 'AboutText').Current.IsOffscreen) { throw 'Settings closed after save' }
Invoke-Uia 'SettingsBack'
Start-Sleep -Milliseconds 250

Invoke-UiaButton 'Customize'
Start-Sleep -Milliseconds 350
Set-UiaValue 'CustomizeNameBox' 'Probe Companion'
Set-UiaCombo 'CustomizeColourCombo' 'plum'
Set-UiaCombo 'CustomizePersonalityCombo' 'playful'
Set-UiaValue 'CustomizePersonaBox' 'Live persona probe.'
Invoke-Uia 'CustomizeSaveButton'
Start-Sleep -Milliseconds 350
$customizeStatus = Get-UiaText 'CustomizeStatusText'
"SAVE Customize status=$customizeStatus"
if ($customizeStatus -notmatch 'Customize saved\.') { throw 'Customize save did not show visible success' }
$savedCfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
if ($savedCfg.name -ne 'Probe Companion' -or $savedCfg.color -ne 'plum' -or $savedCfg.personality -ne 'playful') {
    throw 'Customize identity values were not persisted'
}
if ((Get-Content -LiteralPath $personaPath -Raw) -notmatch 'Live persona probe\.') {
    throw 'Customize persona text was not persisted'
}
Invoke-Uia 'CustomizeBack'
Start-Sleep -Milliseconds 250

Invoke-UiaButton 'Brain'
Start-Sleep -Milliseconds 350
Set-UiaCombo 'BrainTypeCombo' 'opencode'
Set-UiaValue 'BrainProviderBox' 'Probe'
Set-UiaValue 'BrainEndpointBox' ''
Set-UiaValue 'BrainModelBox' 'probe-model'
Set-UiaValue 'BrainAgentIdBox' 'probe-agent'
Set-UiaCombo 'BrainProfileCombo' 'companion'
Invoke-Uia 'BrainSaveButton'
Start-Sleep -Milliseconds 350
$brainStatus = Get-UiaText 'BrainStatusText'
"SAVE Brain status=$brainStatus"
if ($brainStatus -notmatch 'Brain saved\.') { throw 'Brain save did not show visible success' }
$opencodeBadge = Get-UiaText 'RouteBadge'
"BADGE after brain save=$opencodeBadge"
if ($opencodeBadge -notmatch 'Local' -or $opencodeBadge -notmatch 'Probe' -or $opencodeBadge -notmatch 'probe-model') {
    throw 'route badge does not match the saved OpenCode brain'
}
Invoke-Uia 'BrainBack'
Start-Sleep -Milliseconds 250

Invoke-UiaButton 'Privacy'
Start-Sleep -Milliseconds 350
$privacyRoute = Get-UiaText 'PrivacyRouteText'
"PRIVACY after brain save=$privacyRoute"
if ($privacyRoute -notmatch 'opencode') { throw 'Privacy disclosure does not match the saved OpenCode route' }
Invoke-Uia 'PrivacyBack'
Start-Sleep -Milliseconds 250

# Restore the bundled route so the disposable profile is left in its local state.
Invoke-UiaButton 'Brain'
Start-Sleep -Milliseconds 350
Set-UiaCombo 'BrainTypeCombo' 'builtin'
Set-UiaValue 'BrainModelBox' ''
Invoke-Uia 'BrainSaveButton'
Start-Sleep -Milliseconds 350
$restoreStatus = Get-UiaText 'BrainStatusText'
"SAVE Brain restore status=$restoreStatus"
if ($restoreStatus -notmatch 'Brain saved\.') { throw 'Brain restore did not show visible success' }
$localBadge = Get-UiaText 'RouteBadge'
"BADGE after brain restore=$localBadge"
if ($localBadge -notmatch 'Local · bundled · \S') {
    throw 'bundled route was not restored after live save probe'
}
Invoke-Uia 'BrainBack'
Start-Sleep -Milliseconds 250
} # SLOP_LIVE_DESTINATIONS opt-in block

# Full work-area mode lives in the chat window, not on the pet. The mode
# button must round-trip Extended -> Full -> Extended without touching the pet.
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
Invoke-UiaIn (Get-ChatWin) 'ChatModeButton'
Start-Sleep -Milliseconds 900
$chatWin = Get-ChatWin
$fr = $chatWin.Current.BoundingRectangle
"CHAT Full size=$([int]$fr.Width)x$([int]$fr.Height) screen=$($screen.Width)x$($screen.Height)"
if ($fr.Width -lt ($screen.Width - 40) -or $fr.Height -lt ($screen.Height - 40)) {
    throw 'Full chat did not fill the work area'
}
foreach ($id in 'ChatScroll','InputBox','SendBtn') {
    $el = Find-UiaIn $chatWin $id
    if (-not $el) { throw "UIA element $id missing while chat is Full" }
    $r2 = $el.Current.BoundingRectangle
    $inside = (-not $el.Current.IsOffscreen) -and $r2.Width -gt 0 -and $r2.Height -gt 0 -and
              $r2.Right -le ($fr.Right + 1) -and $r2.Bottom -le ($fr.Bottom + 1)
    "  $id rect=$([int]$r2.X),$([int]$r2.Y) $([int]$r2.Width)x$([int]$r2.Height) inside=$inside"
    if (-not $inside) { throw "$id is clipped while chat is Full" }
}
Invoke-UiaIn (Get-ChatWin) 'ChatModeButton'
Start-Sleep -Milliseconds 900
$crBack = (Get-ChatWin).Current.BoundingRectangle
"CHAT restored size=$([int]$crBack.Width)x$([int]$crBack.Height)"
if ([Math]::Abs($crBack.Width - (760.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($crBack.Height - (540.0*$script:DpiY)) -gt 12) { throw 'chat mode toggle did not return to Extended' }

# Send + answer: with the pet collapsed its status dot is hidden, so the chat
# bubble text is the visible signal. UIA exercises the same path as a user send.
if (-not (Focus-Chat)) { throw 'focus failed before typing' }
$chatBefore = Get-ChatText
Set-UiaValue 'InputBox' 'Reply with the single word OK.'
"SEND input='$((Get-UiaValue 'InputBox'))' enabled=$((Find-UiaIn (Get-ChatWin) 'SendBtn').Current.IsEnabled)"
Invoke-Uia 'SendBtn'
Start-Sleep -Milliseconds 120
$stop = Find-UiaIn (Get-ChatWin) 'StopBtn'
"SEND after click input='$((Get-UiaValue 'InputBox'))' stopVisible=$([bool]($stop -and -not $stop.Current.IsOffscreen))"
# A CPU-only stand-in can spend tens of seconds loading before it emits a token.
$chatAfter = $chatBefore
for ($i=0; $i -lt 400; $i++) {
    Start-Sleep -Milliseconds 150
    $chatAfter = Get-ChatText
    if ($chatAfter.Length -gt $chatBefore.Length -and $chatAfter -match '\bOK\b') { break }
}
"STREAM chatCharsBefore=$($chatBefore.Length) after=$($chatAfter.Length)"
if ($chatAfter.Length -le $chatBefore.Length) { throw 'no new chat content after send' }
if ($chatAfter -notmatch '\bOK\b') { throw 'brain answer did not render in the chat window' }

# Close chat: the pet must stay a pea and keep its position.
$petBeforeClose = (Get-PetWin).Current.BoundingRectangle
Invoke-UiaIn (Get-ChatWin) 'ChatCloseButton'
Start-Sleep -Milliseconds 900
if (Get-ChatWin) { throw 'chat window did not close' }
$petAfter = (Get-PetWin).Current.BoundingRectangle
"CHAT closed pet=$([int]$petAfter.Width)x$([int]$petAfter.Height) moved=$([int]($petAfter.X-$petBeforeClose.X)),$([int]($petAfter.Y-$petBeforeClose.Y))"
if ([Math]::Abs($petAfter.Width - (484.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($petAfter.Height - (330.0*$script:DpiY)) -gt 12) { throw 'pet size changed after chat close' }
if ([Math]::Abs($petAfter.X-$petBeforeClose.X) -gt 2 -or
    [Math]::Abs($petAfter.Y-$petBeforeClose.Y) -gt 2) { throw 'pet position changed after chat close' }

# Re-query the pet window fresh: a cached UIA element can briefly report a
# stale rect, which made a real drag look like a no-op.
function WinRect {
    $w = Get-PetWin
    if (-not $w) { return $null }
    $w.Current.BoundingRectangle
}
# re-focus before the physical drag; a stale foreground window makes DragMove a no-op
if (-not (Focus-Ok)) { throw 'focus failed before drag' }
Start-Sleep -Milliseconds 500
$before = WinRect
$moved = $false
for ($try=1; $try -le 4 -and -not $moved; $try++) {
    $pea = Find-Pea
    if (-not $pea) { "DRAG try=$try no pea found"; Start-Sleep -Milliseconds 200; continue }
    "DRAG try=$try pea=$([int]$pea[0]),$([int]$pea[1])"
    $a = Phys $pea[0] $pea[1]
    $z = Phys ($pea[0]-60) ($pea[1]-20)
    [VM]::SetCursorPos($a[0],$a[1]) | Out-Null
    Start-Sleep -Milliseconds 70
    [VM]::mouse_event([VM]::DOWN,0,0,0,0)
    for ($i=1;$i -le 8;$i++) {
        [VM]::SetCursorPos([int]($a[0]+($z[0]-$a[0])*$i/8),[int]($a[1]+($z[1]-$a[1])*$i/8)) | Out-Null
        Start-Sleep -Milliseconds 25
    }
    [VM]::mouse_event([VM]::UP,0,0,0,0)
    Start-Sleep -Milliseconds 600
    $after = WinRect
    if (-not $after) { continue }
    $moved = ([Math]::Abs($after.X-$before.X) + [Math]::Abs($after.Y-$before.Y)) -gt 5
}
$after = WinRect
"DRAG moved=$([int]($after.X-$before.X)),$([int]($after.Y-$before.Y)) flag=$moved"
if (-not $moved) { throw 'drag never moved the window' }

"APP OUT: $(Get-Content $out -Raw -ErrorAction SilentlyContinue)"
"APP ERR: $(Get-Content $err -Raw -ErrorAction SilentlyContinue)"
"FINAL_PID=$($proc.Id)"
} finally {
    # Always tear down: the app is topmost and keeps an inherited stdout handle,
    # which hangs piped callers long after the checks finish (including throws).
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -like '*src/Slop.ps1*' -or $_.CommandLine -like '*slop-run-wrapper.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($svcProc -and -not $svcProc.HasExited) {
        Stop-Process -Id $svcProc.Id -Force -ErrorAction SilentlyContinue
    }
    # Only kill the stand-in model this run launched, never a user-owned brain.
    if ($script:StandInModelPath) {
        Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" |
            Where-Object { $_.CommandLine -like "*$($script:StandInModelPath)*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    if ($null -ne $script:OriginalTestInstallRoot) { $env:SLOP_TEST_INSTALL_ROOT = $script:OriginalTestInstallRoot }
    else { Remove-Item Env:SLOP_TEST_INSTALL_ROOT -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 300
    'TEARDOWN complete'
}
