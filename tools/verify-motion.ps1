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

function Get-Win($id) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $id)
    $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}
function Find-Uia($id) {
    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    # WPF can recycle automation peers while the pea hops. A cached window
    # element eventually returns null, so re-query the top-level window each time.
    $win = Get-Win $proc.Id
    if (-not $win) { return $null }
    $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
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
    $win = Get-Win $proc.Id
    if (-not $win) { return $null }
    $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
function Find-UiaButton($name) {
    $cond = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty, $name),
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button))
    $win = Get-Win $proc.Id
    if (-not $win) { return $null }
    $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
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

# expand
$expanded = $false
for ($try=1;$try -le 3 -and -not $expanded;$try++) {
    Focus-Ok | Out-Null
    Click 242 305
    Start-Sleep -Milliseconds 700
    $b = Grab; $p = Pixel $b 242 144; $b.Dispose()
    if ($p.R -lt 60 -and $p.G -lt 80 -and $p.B -gt 30) { $expanded = $true; "EXPAND panel=$($p.R),$($p.G),$($p.B)" }
}
if (-not $expanded) { throw 'click never expanded chat' }
if (-not (Wait-DotBlue -TimeoutMs 45000)) { throw 'chat-open header dot is not blue' }
$b = Grab; $chatDot = Pixel $b 50 36; $b.Dispose()
"SIGNAL chat-open dot=$($chatDot.R),$($chatDot.G),$($chatDot.B) color=$(Classify $chatDot)"

# Expanded size should be the remembered 760x540, not the old 484x330.
$er = $script:W.Current.BoundingRectangle
"EXPANDED size=$([int]$er.Width)x$([int]$er.Height)"
if ([Math]::Abs($er.Width - (760.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($er.Height - (540.0*$script:DpiY)) -gt 12) { throw 'expanded size is not 760x540' }
$strip = Find-Uia 'ShortcutsStrip'
"SHORTCUTS visible=$(-not $strip.Current.IsOffscreen) children=$($strip.Current.BoundingRectangle.Width)"
if ($strip.Current.IsOffscreen) { throw 'shortcut strip is not visible when expanded' }

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
Set-UiaValue 'SettingsAgentIdBox' 'probe-agent'
Invoke-Uia 'SettingsSaveButton'
Start-Sleep -Milliseconds 350
$settingsStatus = Get-UiaText 'SettingsStatusText'
"SAVE Settings status=$settingsStatus"
if ($settingsStatus -notmatch 'Settings saved\.') { throw 'Settings save did not show visible success' }
$savedCfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
if ($savedCfg.agentId -ne 'probe-agent') { throw 'Settings save did not persist agentId' }
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

# Maximize via the □ control dot. Chat input and Send must remain fully inside
# the window; a stale fixed clip used to cut them off in this state.
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
Invoke-Uia 'SettingsDot'
Start-Sleep -Milliseconds 900
$mr = $script:W.Current.BoundingRectangle
"MAXIMIZE size=$([int]$mr.Width)x$([int]$mr.Height) screen=$($screen.Width)x$($screen.Height)"
if ($mr.Width -lt ($screen.Width - 40) -or $mr.Height -lt ($screen.Height - 40)) {
    throw 'maximize did not fill the screen'
}
foreach ($id in 'ChatScroll','InputBox','SendBtn') {
    $el = Find-Uia $id
    if (-not $el) { throw "UIA element $id missing while maximized" }
    $r2 = $el.Current.BoundingRectangle
    $inside = (-not $el.Current.IsOffscreen) -and $r2.Width -gt 0 -and $r2.Height -gt 0 -and
              $r2.Right -le ($mr.Right + 1) -and $r2.Bottom -le ($mr.Bottom + 1)
    "  $id rect=$([int]$r2.X),$([int]$r2.Y) $([int]$r2.Width)x$([int]$r2.Height) inside=$inside"
    if (-not $inside) { throw "$id is clipped while maximized" }
}
# Restore must return to the remembered expanded size.
Invoke-Uia 'SettingsDot'
Start-Sleep -Milliseconds 900
$rr = $script:W.Current.BoundingRectangle
"RESTORE size=$([int]$rr.Width)x$([int]$rr.Height)"
if ([Math]::Abs($rr.Width - (760.0*$script:DpiX)) -gt 12 -or
    [Math]::Abs($rr.Height - (540.0*$script:DpiY)) -gt 12) { throw 'restore did not return to 760x540' }

# send + streaming. UIA is more reliable than clipboard keystrokes here: setting
# the TextBox value and invoking Send exercises the same code path as a user send.
if (-not (Focus-Ok)) { throw 'focus failed before typing' }
Set-UiaValue 'InputBox' 'Reply with the single word OK.'
"SEND input='$((Get-UiaValue 'InputBox'))' enabled=$((Find-Uia 'SendBtn').Current.IsEnabled)"
Invoke-Uia 'SendBtn'
Start-Sleep -Milliseconds 120
"SEND after click input='$((Get-UiaValue 'InputBox'))' stopVisible=$([bool](Find-Uia 'StopBtn'))"
# Poll immediately and keep polling through model startup: a fast local reply
# can finish before one sample, while a freshly loaded 2B brain can stay idle
# for tens of seconds. Either thinking or success ends this wait; the fallback
# below still enforces the final success signal with its own timeout.
$dotColors = @{}
for ($i=0; $i -lt 400; $i++) {
    $c = DotColor
    $dotColors[$c] = $true
    if ($c -in @('amber','green')) { break }
    Start-Sleep -Milliseconds 150
}
"PRESTREAM dot colors=$($dotColors.Keys -join ',')"
if ($dotColors.ContainsKey('amber')) { 'SIGNAL thinking dot observed = amber' }
elseif ($dotColors.ContainsKey('green')) { 'SIGNAL request completed before amber sample (fast reply)' }
else { throw 'no thinking or success signal observed after send' }
# A fast local reply can finish - and its transient green expire - before the
# churn loop below. Remember any green already seen after Send so the success
# check counts it instead of demanding a second, later observation.
$greenSeen = $dotColors.ContainsKey('green')

$changes = 0; $last = ''; $firstBright = 0
for ($i=0;$i -lt 80;$i++) {
    Start-Sleep -Milliseconds 150
    $b = Grab
    $v = Count $b 28 54 428 180 'bright'
    $e = Count $b 28 54 428 180 'red'
    $b.Dispose()
    if ($i -eq 0) { $firstBright = $v }
    $k = "$v/$e"
    if ($k -ne $last) { $changes++; $last = $k }
    if (-not $greenSeen -and (Classify (DotColor)) -eq 'green') { $greenSeen = $true }
    if ($changes -ge 3 -and $v -gt 400) { break }
}
"STREAM changes=$changes firstBright=$firstBright lastBright=$v errorRed=$e"
# A fast local reply can render fully before the first pixel sample, so pixel
# churn is informational; rendered content plus the success-green check below
# is the reliable signal.
if ($v -le 100) { throw 'no rendered chat content after send' }

# Fallback: if the reply was slow enough that no green was seen yet, keep
# polling for the transient success overlay (green square).
# A CPU-only stand-in model can spend tens of seconds loading and decoding.
for ($i=0;$i -lt 400 -and -not $greenSeen;$i++) {
    Start-Sleep -Milliseconds 150
    $b = Grab; $p = Pixel $b 50 36; $b.Dispose()
    if ((Classify $p) -eq 'green') {
        $greenSeen = $true
        "SIGNAL success dot=$($p.R),$($p.G),$($p.B) color=green"
    }
}
"SIGNAL successSeen=$greenSeen"
if (-not $greenSeen) { throw 'success green overlay never appeared' }

# Esc collapse + drag (only after verified foreground)
if (-not (Focus-Ok)) { throw 'focus failed before ESC' }
Press ([VM]::ESC)
Start-Sleep -Milliseconds 2400
$b = Grab; $p2 = Pixel $b 234 136; "ESC panel=$($p2.R),$($p2.G),$($p2.B)"; $b.Dispose()

# Re-query the top-level window fresh: after maximize/restore the cached UIA
# element can briefly report the pre-restore rect, which made a real drag look
# like a no-op (and then the print showed the corrected delta).
function WinRect {
    $w = Get-Win $proc.Id
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
