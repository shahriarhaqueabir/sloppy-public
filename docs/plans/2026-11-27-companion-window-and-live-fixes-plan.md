# Companion Chat Window and Live UI Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Subagent execution is excluded** by explicit user constraint ("we dont have money to run sub agents"). Execute inline in this session only.

**Goal:** Move expanded and full-work-area chat into one separate, non-topmost WPF window so the pet never moves or resizes; fix the seven live issues found in real use (empty replies, stale wizard preview, dead wheel scroll, loose membrane padding, layered outline, taskbar-stuck pet, lost pet position).

**Architecture:** Keep `Slop.ps1` as the single dispatcher-owned shell. Add a pure, headless-testable `Slop.ChatWindow.ps1` that owns work-area geometry, pet interaction state, and the chat window XAML. The chat window always uses the established transparent WPF surface (`WindowStyle="None"`, `AllowsTransparency="True"`, `Background="Transparent"`) in both extended and full-work-area modes; Mica, Acrylic and DWM backdrop APIs are forbidden and guarded by a static test. The pet window keeps its compact geometry forever; opening chat creates one second window, rebinds the shared chat controls to it, and disables pet input. Built-in-brain replies are recovered from `reasoning_content` through a new `__THINK__` control token so the UI never labels a real answer as empty. Every fix is proven with static/Pester RED tests before source changes.

**Tech Stack:** PowerShell 7.6, WPF via `XamlReader`, Pester 6, `SlopFrame` C# geometry type (Version 4), OpenAI-compatible SSE adapter, OpenCode bridge.

**Approved spec:** `docs/plans/2026-11-27-companion-window-and-live-fixes-design.md` (commit `1126876`).

**Hard gates (unchanged):**
- No push, tag, release, deploy, force-push, visibility change, installer change, brain/provider/route-policy change, or remote change.
- `data/` is untracked user data. Never commit, delete, or sweep it.
- No live visual/interaction claim by the agent. The user performs all live checks.
- Every commit uses an explicit path list; never `git add -A`.

---

## File Structure

| File | Responsibility |
|---|---|
| `src/Slop.ChatWindow.ps1` | **New.** Pure geometry (`Get-SlopWorkAreaClampedRect`, `Get-SlopChatWindowRect`), pet interaction state (`Get-SlopPetInteractionState`), and `Get-SlopChatWindowXaml`. No WPF types at parse time. |
| `tests/slop-chatwindow-check.ps1` | **New.** Pester gates for the pure helpers, chat XAML, one-instance/open/close contract, work-area clamp, wheel scroll, and pet interaction gate. |
| `src/Slop.ps1` | Shell wiring: open/close/toggle chat window, rebind shared controls, pet interaction gate, clamp pet writes, `__THINK__` handling, membrane padding, outline layering, settings shape. |
| `src/Slop.Provider.ps1` | `New-SlopChatRequestBody -DisableThinking` adds `chat_template_kwargs`. |
| `src/Slop.Route.ps1` | Built-in route passes `-DisableThinking $true`. |
| `src/Slop.Lifecycle.ps1` | SSE reader accumulates `reasoning_content` and emits `__THINK__` only when no visible tokens; `Format-SlopThinkingFallback`. |
| `src/Slop.Onboarding.ps1` | Publish `$SampleLine`/`$PreviewPea` to script scope before handlers. |
| `src/Slop.Surfaces.ps1` | Destination contract split into read-only values, dropdowns, editable text. |
| `tests/*.ps1` | Existing focused gates, extended where noted. |
| `.tours/architect-slop-architecture.tour` | 18 anchors; refresh in Task 9. |

Full CI-equivalent command (used in every "Run full CI" step):

```powershell
Import-Module Pester -MinimumVersion 6.0 -Force
$paths = Get-ChildItem -Path tests -Filter "*-check.ps1" |
    Where-Object { $_.Name -ne "slop-opencode-check.ps1" } |
    Select-Object -ExpandProperty FullName
$r = Invoke-Pester -Path $paths -CI -PassThru -Output None
"FAILED=$($r.FailedCount) PASSED=$($r.PassedCount)"
if ($r.FailedCount -ne 0) { exit 1 }
```

---

### Task 1: Pure chat-window contract module

**Files:**
- Create: `src/Slop.ChatWindow.ps1`
- Create: `tests/slop-chatwindow-check.ps1`

- [ ] **Step 1: Write the RED test**

```powershell
# tests/slop-chatwindow-check.ps1
#requires -Version 7.6
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
. (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1')

Describe 'Slop.ChatWindow pure contract' {
    It 'clamps a requested rect inside the work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopWorkAreaClampedRect -Left 1700 -Top 900 -Width 760 -Height 540 -WorkArea $wa
        $r.Left   | Should -Be 1160
        $r.Top    | Should -Be 500
        $r.Width  | Should -Be 760
        $r.Height | Should -Be 540
    }

    It 'never produces a zero or negative extent' {
        $wa = @{ X = 0; Y = 0; Width = 800; Height = 600 }
        $r = Get-SlopWorkAreaClampedRect -Left -50 -Top -50 -Width 5000 -Height 5000 -WorkArea $wa
        $r.Left | Should -Be 0
        $r.Top  | Should -Be 0
        $r.Width | Should -Be 800
        $r.Height | Should -Be 600
    }

    It 'places the extended window next to the pet and clamps near the taskbar' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $near = Get-SlopChatWindowRect -PetLeft 100 -PetTop 100 -WorkArea $wa
        $near.Left | Should -Be 150
        $near.Top  | Should -Be 0
        $near.Width | Should -Be 760
        $near.Height | Should -Be 540
        $far = Get-SlopChatWindowRect -PetLeft 1700 -PetTop 900 -WorkArea $wa
        $far.Left | Should -Be 1160
        $far.Top  | Should -Be 500
    }

    It 'uses the whole work area in Full mode' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopChatWindowRect -PetLeft 100 -PetTop 100 -WorkArea $wa -Mode Full
        $r.Left | Should -Be 0
        $r.Top | Should -Be 0
        $r.Width | Should -Be 1920
        $r.Height | Should -Be 1040
    }

    It 'disables and restores pet interaction without moving the pet' {
        $open = Get-SlopPetInteractionState -ChatOpen $true
        $open.IsHitTestVisible | Should -BeFalse
        $open.Topmost | Should -BeFalse
        $open.Cursor | Should -Be 'Arrow'
        $closed = Get-SlopPetInteractionState -ChatOpen $false
        $closed.IsHitTestVisible | Should -BeTrue
        $closed.Topmost | Should -BeTrue
        $closed.Cursor | Should -Be 'Hand'
    }

    It 'parses the chat window XAML with all shared control names and no topmost' {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        $win = [System.Windows.Markup.XamlReader]::Parse((Get-SlopChatWindowXaml))
        try {
            foreach ($name in @('ChatRoot','ChatScroll','ChatStack','ShortcutsStrip',
                                'InputBox','InputPlaceholder','MicBtn','SendBtn','StopBtn',
                                'ChatModeButton','ChatCloseButton')) {
                $win.FindName($name) | Should -Not -BeNull
            }
            $win.Topmost | Should -BeFalse
            $win.ResizeMode | Should -Be ([System.Windows.ResizeMode]::CanResize)
            $scroll = $win.FindName('ChatScroll')
            $scroll.VerticalScrollBarVisibility | Should -Be ([System.Windows.Controls.ScrollBarVisibility]::Auto)
        } finally { $win.Close() }
    }

    It 'keeps the transparent surface and never applies Mica or a DWM backdrop' {
        $xaml = Get-SlopChatWindowXaml
        $xaml | Should -Match 'WindowStyle="None"'
        $xaml | Should -Match 'AllowsTransparency="True"'
        $xaml | Should -Match 'Background="Transparent"'
        $xaml | Should -Not -Match 'Mica|Acrylic|Backdrop|DwmSetWindowAttribute|SetWindowCompositionAttribute'
        $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
        $src | Should -Not -Match 'Mica|Acrylic|DwmSetWindowAttribute|SetWindowCompositionAttribute'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: RED — "The term 'Get-SlopWorkAreaClampedRect' is not recognized" (all seven assertions fail at dot-source).

- [ ] **Step 3: Write the minimal implementation**

```powershell
# src/Slop.ChatWindow.ps1
# Pure geometry, interaction state and XAML for the separate chat window.
# No WPF types are constructed when this file is dot-sourced headlessly.
$ErrorActionPreference = 'Stop'

function Get-SlopWorkAreaClampedRect {
    param(
        [Parameter(Mandatory)][double]$Left,
        [Parameter(Mandatory)][double]$Top,
        [Parameter(Mandatory)][double]$Width,
        [Parameter(Mandatory)][double]$Height,
        [Parameter(Mandatory)]$WorkArea
    )
    $waX = [double]$WorkArea.X
    $waY = [double]$WorkArea.Y
    $waW = [double]$WorkArea.Width
    $waH = [double]$WorkArea.Height
    $w = [Math]::Min([Math]::Max(1.0, $Width), $waW)
    $h = [Math]::Min([Math]::Max(1.0, $Height), $waH)
    $x = [Math]::Max($waX, [Math]::Min($Left, $waX + $waW - $w))
    $y = [Math]::Max($waY, [Math]::Min($Top, $waY + $waH - $h))
    return @{ Left = $x; Top = $y; Width = $w; Height = $h }
}

function Get-SlopChatWindowRect {
    param(
        [Parameter(Mandatory)][double]$PetLeft,
        [Parameter(Mandatory)][double]$PetTop,
        [double]$PetWidth = 26.0,
        [double]$PetHeight = 26.0,
        [Parameter(Mandatory)]$WorkArea,
        [ValidateSet('Extended','Full')][string]$Mode = 'Extended',
        [double]$ExtendedWidth = 760.0,
        [double]$ExtendedHeight = 540.0
    )
    if ($Mode -eq 'Full') {
        return Get-SlopWorkAreaClampedRect -Left ([double]$WorkArea.X) -Top ([double]$WorkArea.Y) `
            -Width ([double]$WorkArea.Width) -Height ([double]$WorkArea.Height) -WorkArea $WorkArea
    }
    $left = $PetLeft + $PetWidth + 24.0
    $top = $PetTop + ($PetHeight - $ExtendedHeight) / 2.0
    return Get-SlopWorkAreaClampedRect -Left $left -Top $top `
        -Width $ExtendedWidth -Height $ExtendedHeight -WorkArea $WorkArea
}

function Get-SlopPetInteractionState {
    param([bool]$ChatOpen)
    if ($ChatOpen) { return @{ IsHitTestVisible = $false; Topmost = $false; Cursor = 'Arrow' } }
    return @{ IsHitTestVisible = $true; Topmost = $true; Cursor = 'Hand' }
}

function Get-SlopChatWindowXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sloppy chat" MinWidth="468" MinHeight="330" Width="760" Height="540"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="False" ResizeMode="CanResize" ShowInTaskbar="True"
        WindowStartupLocation="Manual" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="SlopChatComboBoxItem" TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
    </Style>
    <Style x:Key="SlopChatComboBox" TargetType="ComboBox">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource SlopChatComboBoxItem}"/>
    </Style>
  </Window.Resources>
  <Grid x:Name="ChatRoot">
    <Grid.RowDefinitions>
      <RowDefinition Height="34"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border x:Name="ChatChrome" Grid.Row="0" Background="#221E293B"
            BorderBrush="#44FFFFFF" BorderThickness="1" CornerRadius="12,12,0,0">
      <Grid>
        <TextBlock Text="S.L.O.P. chat" Foreground="#EAEAEA" FontWeight="SemiBold"
                   FontSize="12" VerticalAlignment="Center" Margin="12,0,0,0"
                   IsHitTestVisible="False"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
          <Button x:Name="ChatModeButton" Width="22" Height="22" Content="□"
                  ToolTip="Toggle chat size" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="9"
                  AutomationProperties.Name="Toggle chat size"/>
          <Button x:Name="ChatCloseButton" Width="22" Height="22" Content="X"
                  ToolTip="Close chat" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="9"
                  AutomationProperties.Name="Close chat"/>
        </StackPanel>
      </Grid>
    </Border>
    <Grid Grid.Row="1" Margin="12,6,12,6">
      <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="ChatStack"/>
      </ScrollViewer>
    </Grid>
    <Border Grid.Row="2" Margin="12,0,12,12" Padding="8" CornerRadius="10"
            Background="#221E293B" BorderBrush="#44FFFFFF" BorderThickness="1">
      <StackPanel>
        <WrapPanel x:Name="ShortcutsStrip" Margin="0,0,0,6"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="InputBox" Height="32" FontSize="13" Padding="7,4"
                   Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                   VerticalContentAlignment="Center"/>
          <TextBlock x:Name="InputPlaceholder" Grid.Column="0" Text="Say something..."
                     Foreground="#8A8A96" FontSize="13" Margin="11,0,0,0"
                     VerticalAlignment="Center" IsHitTestVisible="False"/>
          <Button x:Name="MicBtn" Grid.Column="1" Content="🎤" Width="34" Height="32"
                  Margin="6,0,0,0" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Voice input"/>
          <Button x:Name="SendBtn" Grid.Column="2" Content="Send" Width="54" Height="32"
                  Margin="6,0,0,0" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Send message"/>
          <Button x:Name="StopBtn" Grid.Column="3" Content="Stop" Width="54" Height="32"
                  Margin="6,0,0,0" Visibility="Collapsed" Background="#33BFDBFE"
                  Foreground="#EAEAEA" BorderBrush="#55FFFFFF" BorderThickness="1"
                  Cursor="Hand" AutomationProperties.Name="Stop request"/>
        </Grid>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
}
```

- [ ] **Step 4: Run test to verify it passes**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: GREEN 7/0.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ChatWindow.ps1 tests/slop-chatwindow-check.ps1
git commit -m "test: chat window geometry and interaction contract (RED->GREEN)"
```

---

### Task 2: Built-in brain visible answers

**Files:**
- Modify: `src/Slop.Provider.ps1:88-128`
- Modify: `src/Slop.Route.ps1:156`
- Modify: `src/Slop.Lifecycle.ps1:159-207,252-256`
- Modify: `src/Slop.Provider.ps1:8-12`
- Modify: `src/Slop.ps1:1809-1825`
- Modify: `tests/slop-lifecycle-check.ps1`, `tests/slop-provider-check.ps1`

- [ ] **Step 1: Write the RED tests**

Append to `tests/slop-lifecycle-check.ps1` before the final `Describe`/`It` block:

```powershell
Assert-True ((Get-Command Format-SlopThinkingFallback -ErrorAction SilentlyContinue) -ne $null) `
    'thinking fallback formatter exists'
$fb = Format-SlopThinkingFallback -Thinking '  hidden answer  ' -VisibleText ''
Assert-True ($fb -eq '[thinking] hidden answer') 'reasoning becomes labelled fallback text'
Assert-True ($null -eq (Format-SlopThinkingFallback -Thinking 'x' -VisibleText 'visible')) `
    'visible text is never replaced by thinking'

$thinkQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$thinkSse = @(
    'data: {"choices":[{"delta":{"content":""}}]}',
    'data: {"choices":[{"delta":{"reasoning_content":"hel"}}]}',
    'data: {"choices":[{"delta":{"reasoning_content":"lo"}}]}',
    'data: [DONE]'
) -join "`n"
$thinkStats = Read-SlopSseStream -Reader ([System.IO.StringReader]::new($thinkSse)) -Queue $thinkQueue
$thinkTokens = @(); $thinkTok = $null
while ($thinkQueue.TryDequeue([ref]$thinkTok)) { $thinkTokens += $thinkTok }
Assert-True ($thinkStats.Tokens -eq 0 -and $thinkStats.Thinking -eq 'hello') `
    'SSE reader accumulates reasoning_content separately from visible tokens'
Assert-True ($thinkTokens.Count -eq 1 -and $thinkTokens[0] -eq '__THINK__hello') `
    'a reasoning-only stream emits exactly one __THINK__ control token'

$bothQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$bothSse = @(
    'data: {"choices":[{"delta":{"content":"shown","reasoning_content":"hidden"}}]}',
    'data: [DONE]'
) -join "`n"
$bothStats = Read-SlopSseStream -Reader ([System.IO.StringReader]::new($bothSse)) -Queue $bothQueue
$bothTokens = @(); $bothTok = $null
while ($bothQueue.TryDequeue([ref]$bothTok)) { $bothTokens += $bothTok }
Assert-True (($bothTokens -join '') -eq 'shown') `
    'a stream with visible content never emits __THINK__'
Assert-True ((Resolve-SlopStreamToken -Token '__THINK__hello').Kind -eq 'thinking') `
    '__THINK__ is classified as a distinct lifecycle kind'
```

Add to `tests/slop-provider-check.ps1` inside `Describe 'Slop.Provider'`:

```powershell
It 'asks the bundled model to disable thinking only on the local route' {
    $body = New-SlopChatRequestBody -SystemPrompt '' -UserText 'hi' -DisableThinking | ConvertFrom-Json
    $body.chat_template_kwargs.enable_thinking | Should -BeFalse
    $plain = New-SlopChatRequestBody -SystemPrompt '' -UserText 'hi' | ConvertFrom-Json
    $plain.PSObject.Properties.Name | Should -Not -Contain 'chat_template_kwargs'
    $routeSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Route.ps1') -Raw
    $routeSrc | Should -Match 'DisableThinking \$true'
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path tests/slop-lifecycle-check.ps1,tests/slop-provider-check.ps1 -Output Detailed
```

Expected: RED — missing `Format-SlopThinkingFallback`, missing `Thinking` on reader stats, no `DisableThinking` parameter.

- [ ] **Step 3: Implement the fallback**

In `src/Slop.Provider.ps1`, change `Get-SlopAdapterContract` marker list:

```powershell
        MarkerContract = @('__DONE__', '__CONNECTED__', '__WARN__', '__ERR__', '__TOK__', '__OC', '__THINK__')
```

Replace the whole `New-SlopChatRequestBody` function in `src/Slop.Provider.ps1:88-128` with:

```powershell
function New-SlopChatRequestBody {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SystemPrompt,
        [Parameter(Mandatory)][AllowEmptyString()][string]$UserText,
        [object[]]$History = @(),
        [object[]]$Attachments = @(),
        [int]$MaxLength = 8000,
        [switch]$DisableThinking
    )
    if ($UserText.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    $messages = [Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $messages.Add(@{ role = 'system'; content = $SystemPrompt })
    }
    foreach ($item in @($History | Select-Object -Last 24)) {
        $role = [string]$item.role
        $content = [string]$item.content
        if ($role -notin @('user','assistant')) { throw 'history role must be user or assistant' }
        if ($content.Length -gt $MaxLength) { throw "history message exceeds $MaxLength characters" }
        $messages.Add(@{ role = $role; content = $content })
    }
    $atts = @($Attachments | Where-Object { $null -ne $_ })
    if ($atts.Count -gt 0) {
        $parts = [Collections.Generic.List[object]]::new()
        $parts.Add(@{ type = 'text'; text = $UserText })
        foreach ($att in $atts) {
            $ht = if ($att -is [hashtable]) { $att } else { @{}; foreach ($p in $att.PSObject.Properties) { $ht[$p.Name] = $p.Value }; $ht }
            $parts.Add((ConvertTo-SlopChatContentPart -Attachment $ht))
        }
        $messages.Add(@{ role = 'user'; content = $parts.ToArray() })
    } else {
        $messages.Add(@{ role = 'user'; content = $UserText })
    }
    $result = @{
        model       = 'sloppy'
        messages    = $messages.ToArray()
        stream      = $true
        temperature = 0.8
        max_tokens  = 512
    }
    if ($DisableThinking) {
        $result.chat_template_kwargs = @{ enable_thinking = $false }
    }
    return $result | ConvertTo-Json -Depth 8 -Compress
}
```

In `src/Slop.Route.ps1`, replace line 156:

```powershell
    $body = New-SlopChatRequestBody -SystemPrompt $PersonaText -UserText $UserText -History $History -Attachments $Attachments -DisableThinking
```

In `src/Slop.Lifecycle.ps1`, replace the whole `Read-SlopSseStream` body from `$malformed = 0` through the final `return`:

```powershell
    $malformed = 0
    $tokens = 0
    $thinking = ''
    while ($true) {
        if ($Token.IsCancellationRequested) {
            return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
        }
        try {
            $line = $Reader.ReadLineAsync($Token).GetAwaiter().GetResult()
        }
        catch [System.OperationCanceledException] {
            return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
        }
        catch [System.ObjectDisposedException] {
            if ($Token.IsCancellationRequested) {
                return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
            }
            throw
        }
        if ($null -eq $line) {
            if ($Token.IsCancellationRequested) {
                return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $true; Thinking = $thinking }
            }
            break
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:')) { continue }
        $data = $line.Substring(5).Trim()
        if ($data -eq '[DONE]') { break }
        try {
            $obj = $data | ConvertFrom-Json -ErrorAction Stop
            $delta = $obj.choices[0].delta.content
            if ($delta) {
                $Queue.Enqueue([string]$delta)
                $tokens++
            }
            $reasoning = $obj.choices[0].delta.reasoning_content
            if ($reasoning) { $thinking += [string]$reasoning }
        } catch {
            $malformed++
        }
    }
    # Only surface thinking when the model produced no visible answer. A real
    # answer must never be replaced or prefixed by its hidden reasoning.
    if ($tokens -eq 0 -and -not [string]::IsNullOrWhiteSpace($thinking)) {
        $Queue.Enqueue('__THINK__' + $thinking)
    }
    return @{ Malformed = $malformed; Tokens = $tokens; Cancelled = $false; Thinking = $thinking }
```

Add classification in `Resolve-SlopStreamToken` before the `__TOK__` branch:

```powershell
    if ($Token.StartsWith('__THINK__')) {
        return @{ Kind = 'thinking'; Reason = $null; Text = $Token.Substring(9) }
    }
```

Append after `Format-SlopEmptyResponse`:

```powershell
function Format-SlopThinkingFallback {
    param([string]$Thinking, [string]$VisibleText)
    if (-not [string]::IsNullOrWhiteSpace($VisibleText)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Thinking)) { return $null }
    return '[thinking] ' + $Thinking.Trim()
}
```

In `src/Slop.ps1`, publish pending thinking at script state (near `$script:CurrentAssistantText` at line 561):

```powershell
$script:PendingThinking = ''
```

Insert this arm into the dispatcher `switch ($ev.Kind)` (source line 1769) immediately before the `'done'` branch. It is shown inside a minimal `switch` so the block parses standalone; only the `'thinking'` arm is new:

```powershell
switch ($ev.Kind) {
    'thinking' {
        $script:PendingThinking = $ev.Text
    }
}
```

Replace the `'done'` empty-label block:

```powershell
                    if (-not $script:Failed) {
                        $fallback = Format-SlopThinkingFallback -Thinking $script:PendingThinking -VisibleText $script:CurrentAssistantText
                        $emptyLabel = if ($fallback) { $fallback } else { Format-SlopEmptyResponse -Text $script:CurrentAssistantText }
                        if ($emptyLabel) {
                            $script:CurrentAssistantBlock.Child.Text = $emptyLabel
                            $script:CurrentAssistantText = $emptyLabel
                            Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind error `
                                -Status 'Request returned no visible text' -DurationSeconds 2.0
                        }
                        else {
                            Set-SlopSignalEvent -State $script:Motion -Id "completion:$gen" -Kind success `
                                -Status 'Request complete' -DurationSeconds 1.5
                        }
                    }
                    $script:PendingThinking = ''
```

Also reset `$script:PendingThinking = ''` at the start of `Start-Stream` (immediately after the `if ($script:IsStreaming) { return }` guard).

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-lifecycle-check.ps1,tests/slop-provider-check.ps1,tests/slop-route-check.ps1 -Output Detailed
```

Expected: GREEN. Then run full CI (command above): expected `FAILED=0`.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Provider.ps1 src/Slop.Route.ps1 src/Slop.Lifecycle.ps1 src/Slop.ps1 tests/slop-lifecycle-check.ps1 tests/slop-provider-check.ps1
git commit -m "fix: recover built-in brain answers from reasoning_content"
```

---

### Task 3: Wizard preview handler scope

**Files:**
- Modify: `src/Slop.Onboarding.ps1:210-215,284-287,302-306`
- Modify: `tests/slop-onboarding-check.ps1:108-120`

- [ ] **Step 1: Write the RED test**

Add to `tests/slop-onboarding-check.ps1`:

```powershell
It 'never reads a function-local XAML variable from an event handler' {
    $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.Onboarding.ps1') -Raw
    $src | Should -Match '\$script:PreviewPea = \$dlg\.FindName\(''PreviewPea''\)'
    $src | Should -Match '\$script:SampleLine = \$dlg\.FindName\(''SampleLine''\)'
    $src | Should -Match '\$script:PreviewPea\.Fill ='
    $src | Should -Match '\$script:SampleLine\.Text ='
    $src | Should -Not -Match '(?m)^\s+\$PreviewPea\.Fill ='
    $src | Should -Not -Match '(?m)^\s+\$SampleLine\.Text ='
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-onboarding-check.ps1 -Output Detailed
```

Expected: RED 1 failing assertion (handler still uses function locals).

- [ ] **Step 3: Publish controls to script scope**

Replace the two `FindName` lines (213, 215):

```powershell
    $script:PreviewPea = $dlg.FindName('PreviewPea')
    $script:SampleLine = $dlg.FindName('SampleLine')
```

Replace the swatch handler at 284-287:

```powershell
        $swatch.Add_Click({ param($s,$e)
            $script:SelectedColor = [string]$s.Tag
            $script:PreviewPea.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString((Get-SlopIdentityColor -ColorKey $script:SelectedColor))
        })
```

Replace line 290:

```powershell
    $script:PreviewPea.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString((Get-SlopIdentityColor -ColorKey $script:SelectedColor))
```

Replace the preset handler at 302-306:

```powershell
        $radio.Add_Checked({ param($s,$e)
            $script:SelectedPreset = [string]$s.Tag
            $sample = Get-SlopPersonaPresets | Where-Object { $_.Id -eq $script:SelectedPreset } | Select-Object -First 1
            if ($sample) { $script:SampleLine.Text = $sample.Sample }
        })
```

Replace line 310:

```powershell
    if ($initialSample) { $script:SampleLine.Text = $initialSample.Sample }
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-onboarding-check.ps1 -Output Detailed
```

Expected: GREEN. Existing "binds every named wizard control" test also stays green because `$dlg.FindName('...')` is still present.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Onboarding.ps1 tests/slop-onboarding-check.ps1
git commit -m "fix: wizard preview updates from script-scope controls"
```

---

### Task 4: Separate chat window wiring in the shell

**Files:**
- Modify: `src/Slop.ps1:342-359` (dot-source + FindName), `528-556` (control dots), `760-817` (Expand/Collapse), `915-934` (blob), `1866-1871` (send), `1983-2042` (input handlers), `2218+` (Closed)
- Modify: `tests/slop-shell-check.ps1:94-99`
- Modify: `tools/verify-motion.ps1:557,574`

- [ ] **Step 1: Write the RED test**

Add to `tests/slop-chatwindow-check.ps1`:

```powershell
Describe 'Slop shell chat-window wiring' {
    BeforeAll {
        $script:AppSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
    }

    It 'dot-sources the chat window module before it is used' {
        $script:AppSrc | Should -Match 'Slop\.ChatWindow\.ps1'
    }

    It 'opens one chat window, brings an existing one to front, and never resizes the pet' {
        $script:AppSrc | Should -Match 'function Open-SlopChatWindow'
        $script:AppSrc | Should -Match '\$script:ChatWindow\.Activate\(\)'
        $script:AppSrc | Should -Not -Match '\$window\.Width = \$script:ExpandedSize\.Width'
    }

    It 'rebinds the shared chat controls to the chat window' {
        foreach ($id in @('ChatScroll','ChatStack','ShortcutsStrip','InputBox','MicBtn','SendBtn','StopBtn')) {
            $script:AppSrc | Should -Match "FindName\('$id'\)"
        }
    }

    It 'uses the open-chat automation name on the pet button' {
        $script:AppSrc | Should -Match 'Content="□" ToolTip="Open chat window" AutomationProperties.Name="Open chat window"'
    }

    It 'restores pet interaction on chat close' {
        $script:AppSrc | Should -Match 'Set-SlopPetChatInteraction -ChatOpen \$false'
        $script:AppSrc | Should -Match '\$script:ChatWindow\.Add_Closed'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: RED 5 failing assertions.

- [ ] **Step 3: Wire the window**

At the module dot-source list near the top of `src/Slop.ps1` (with the other `. (Join-Path $PSScriptRoot ...)` lines), add:

```powershell
. (Join-Path $PSScriptRoot 'Slop.ChatWindow.ps1')
```

Change the `SettingsDot` XAML (lines 109-112) to:

```powershell
          <Button x:Name="SettingsDot" Width="18" Height="18" Margin="0,0,4,0"
                  Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                  BorderThickness="1" BorderBrush="#55FFFFFF" Cursor="Hand" FontSize="9" FontWeight="Bold"
                  Content="□" ToolTip="Open chat window" AutomationProperties.Name="Open chat window"/>
```

Replace the pseudo-max block (lines 528-552) with the chat-window controller:

```powershell
$script:ChatWindow = $null
$script:ChatMode = 'Extended'
$script:PetControls = @{}

function Set-SlopPetChatInteraction {
    param([bool]$ChatOpen)
    $state = Get-SlopPetInteractionState -ChatOpen $ChatOpen
    $PeaCanvas.IsHitTestVisible = [bool]$state.IsHitTestVisible
    $window.Topmost = [bool]$state.Topmost
    $DragHandle.Cursor = $state.Cursor
    $ControlDots.IsHitTestVisible = [bool]$state.IsHitTestVisible
}

function Save-SlopMainChatControls {
    $script:PetControls = @{
        ChatScroll = $window.FindName('ChatScroll')
        ChatStack = $window.FindName('ChatStack')
        ShortcutsStrip = $window.FindName('ShortcutsStrip')
        InputBox = $window.FindName('InputBox')
        InputPlaceholder = $window.FindName('InputPlaceholder')
        MicBtn = $window.FindName('MicBtn')
        SendBtn = $window.FindName('SendBtn')
        StopBtn = $window.FindName('StopBtn')
    }
}
$script:PetControls = @{
    ChatScroll = $ChatScroll; ChatStack = $ChatStack
    ShortcutsStrip = $ShortcutsStrip; InputBox = $InputBox
    InputPlaceholder = $InputPlaceholder; MicBtn = $MicBtn
    SendBtn = $SendBtn; StopBtn = $StopBtn
}

function Use-SlopChatControls {
    param([Parameter(Mandatory)]$Target)
    $script:ChatScroll = $Target.FindName('ChatScroll')
    $script:ChatStack = $Target.FindName('ChatStack')
    $script:ShortcutsStrip = $Target.FindName('ShortcutsStrip')
    $script:InputBox = $Target.FindName('InputBox')
    $script:InputPlaceholder = $Target.FindName('InputPlaceholder')
    $script:MicBtn = $Target.FindName('MicBtn')
    $script:SendBtn = $Target.FindName('SendBtn')
    $script:StopBtn = $Target.FindName('StopBtn')
}

function Restore-SlopMainChatControls {
    $script:ChatScroll = $script:PetControls.ChatScroll
    $script:ChatStack = $script:PetControls.ChatStack
    $script:ShortcutsStrip = $script:PetControls.ShortcutsStrip
    $script:InputBox = $script:PetControls.InputBox
    $script:InputPlaceholder = $script:PetControls.InputPlaceholder
    $script:MicBtn = $script:PetControls.MicBtn
    $script:SendBtn = $script:PetControls.SendBtn
    $script:StopBtn = $script:PetControls.StopBtn
}
```

Convert the shared input handlers (lines 1983, 2030-2042) into script-scope scriptblocks so both windows can bind them. Replace those blocks with:

```powershell
$script:SlopMicAction = { Invoke-SlopVoiceToggle }
$script:SlopStopAction = { Request-StopStream }
$script:SlopSendAction = {
    $text = $script:InputBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $script:InputBox.Text = ''
    Start-Stream -UserText $text
}
$script:SlopInputChangedAction = {
    $script:InputPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($script:InputBox.Text)) { 'Visible' } else { 'Collapsed' }
}
$script:SlopInputKeyDownAction = {
    param($s,$e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter -and -not $e.KeyboardDevice.Modifiers) {
        & $script:SlopSendAction
        $e.Handled = $true
    }
}

function Initialize-SlopChatControlHandlers {
    param([Parameter(Mandatory)]$Target)
    $Target.FindName('MicBtn').Add_Click($script:SlopMicAction)
    $Target.FindName('SendBtn').Add_Click($script:SlopSendAction)
    $Target.FindName('StopBtn').Add_Click($script:SlopStopAction)
    $Target.FindName('InputBox').Add_TextChanged($script:SlopInputChangedAction)
    $Target.FindName('InputBox').Add_KeyDown($script:SlopInputKeyDownAction)
}
Initialize-SlopChatControlHandlers -Target $window
```

Replace `$sendAction` at 1866-1871 with:

```powershell
$sendAction = $script:SlopSendAction
```

Replace `Expand-Chat` and `Collapse-Chat` (760-817) with:

```powershell
function Set-SlopChatWindowRect {
    param([ValidateSet('Extended','Full')][string]$Mode)
    $wa = [System.Windows.SystemParameters]::WorkArea
    $r = Get-SlopChatWindowRect -PetLeft $window.Left -PetTop $window.Top `
        -WorkArea $wa -Mode $Mode
    $script:ChatWindow.Left = $r.Left
    $script:ChatWindow.Top = $r.Top
    $script:ChatWindow.Width = $r.Width
    $script:ChatWindow.Height = $r.Height
    $script:ChatMode = $Mode
    $script:ChatWindow.FindName('ChatModeButton').Content = if ($Mode -eq 'Full') { '_' } else { '□' }
}

function Open-SlopChatWindow {
    if ($script:ChatWindow -and $script:ChatWindow.IsLoaded) {
        $script:ChatWindow.Activate()
        return
    }
    try {
        $chat = [System.Windows.Markup.XamlReader]::Parse((Get-SlopChatWindowXaml))
    } catch {
        Add-Bubble -Text "[error: chat window could not open: $($_.Exception.Message)]" -IsUser $false
        return
    }
    $script:ChatWindow = $chat
    $script:ChatMode = 'Extended'
    Use-SlopChatControls -Target $chat
    Initialize-SlopChatControlHandlers -Target $chat
    Set-SlopChatWindowRect -Mode 'Extended'
    $chat.FindName('ChatModeButton').Add_Click({
        $newMode = if ($script:ChatMode -eq 'Full') { 'Extended' } else { 'Full' }
        Set-SlopChatWindowRect -Mode $newMode
    })
    $chat.FindName('ChatCloseButton').Add_Click({ Collapse-Chat })
    $chat.Add_Closed({
        if ($script:ChatWindow -eq $chat) { $script:ChatWindow = $null }
        Restore-SlopMainChatControls
        Set-SlopPetChatInteraction -ChatOpen $false
    })
    Set-SlopPetChatInteraction -ChatOpen $true
    $chat.Show()
    $chat.FindName('InputBox').Focus() | Out-Null
}

function Expand-Chat { Open-SlopChatWindow }

function Collapse-Chat {
    Request-StopStream
    if ($script:ChatWindow) {
        $chat = $script:ChatWindow
        $script:ChatWindow = $null
        $chat.Close()
    }
    Restore-SlopMainChatControls
    Set-SlopPetChatInteraction -ChatOpen $false
    Set-SlopFrameTarget -State $script:Motion -Target 'closed'
    Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $false -Stalled $false
}
```

Replace the `SettingsDot.Add_Click` line (553) with:

```powershell
$SettingsDot.Add_Click({ Open-SlopChatWindow })
```

In `Finish-Stream` (line 898), change:

```powershell
    Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen ([bool]$script:ChatWindow) -Stalled $false
```

And replace line 905:

```powershell
    if ($script:ChatWindow) { $script:InputBox.Focus() | Out-Null }
```

In `Apply-SlopMotion`, replace the whole branch at source lines 716-746 with this block. `$script:Expanded` becomes `[bool]$script:ChatWindow`, and the `$script:RestoreCompact` resize block at 717-723 is removed because the pet no longer resizes when chat closes:

```powershell
    if ($bodyClosed -and -not $script:ChatWindow -and $script:Frame.Opacity -lt 0.02) {
        $BodyPath.Visibility = 'Collapsed'
        $HeadHighlight.Visibility = 'Collapsed'
        $Frame.Visibility = 'Collapsed'
        $PeaCanvas.Visibility = 'Visible'
    }
    else {
        if (-not $bodyClosed) {
            $BodyPath.Data = [System.Windows.Media.Geometry]::Parse($script:Membrane.Path)
            $BodyPath.Opacity = 1.0
            $BodyPath.Visibility = 'Visible'
            $hl = $script:Membrane.Highlight
            if ($hl) {
                $HeadHighlight.Data = [System.Windows.Media.Geometry]::Parse($hl)
                $HeadHighlight.Opacity = [Math]::Min(1.0, 0.55 + 0.10 * $m.OpenPulse.Value)
                $HeadHighlight.Visibility = 'Visible'
            }
            else { $HeadHighlight.Visibility = 'Collapsed' }
        }
        # Clip is rebuilt on resize (see SizeChanged); opacity follows the opening.
        $Frame.Opacity = [double]$script:Membrane.ContentOpacity
        $Frame.Visibility = 'Visible'
        $PeaCanvas.Visibility = 'Collapsed'
    }
```

Update the control-action name table in `tests/slop-shell-check.ps1:94-98` so the first entry reads:

```powershell
    foreach ($action in @(
        @{ Id = 'SettingsDot'; Name = 'Open chat window' },
        @{ Id = 'PinDot'; Name = 'Collapse Slop to pea' },
        @{ Id = 'CloseDot'; Name = 'Minimize Slop to tray' }
    )) {
        $button = $w.FindName($action.Id)
        Assert-True ($button -is [System.Windows.Controls.Button]) "$($action.Id) remains a button"
        if ($button) {
            Assert-True ([System.Windows.Automation.AutomationProperties]::GetName($button) -eq $action.Name) "$($action.Id) has an accessible action name"
        }
    }
```

Update `tools/verify-motion.ps1` lines 557 and 574: replace `SettingsDot` probes with `ChatModeButton` probes (same `Pixel`/`Grab` helpers; assert the chat window's mode button toggles from `□` to `_`).

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1,tests/slop-shell-check.ps1,tests/slop-expand-check.ps1 -Output Detailed
```

Expected: GREEN. Then full CI: `FAILED=0`. Tour anchors are refreshed in Task 9.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ps1 tests/slop-chatwindow-check.ps1 tests/slop-shell-check.ps1 tools/verify-motion.ps1
git commit -m "feat: open chat in one separate window without moving the pet"
```

---

### Task 5: Work-area clamp on the pet

**Files:**
- Modify: `src/Slop.ps1:420-446`
- Modify: `tests/slop-chatwindow-check.ps1`

- [ ] **Step 1: Write the RED test**

```powershell
It 'clamps every pet position write to the work area' {
    $script:AppSrc | Should -Match '\$window\.Add_LocationChanged'
    $script:AppSrc | Should -Match 'Get-SlopWorkAreaClampedRect -Left \$window\.Left'
    $script:AppSrc | Should -Match '\$window\.Left = \$r\.Left'
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: RED 1 assertion.

- [ ] **Step 3: Clamp pet writes**

Replace the position/resize block at 419-446 with:

```powershell
# park on the primary monitor, top-left area so it is always visible
$script:WorkArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = 100
$window.Top = 100

function Set-SlopPetRectInWorkArea {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $r = Get-SlopWorkAreaClampedRect -Left $window.Left -Top $window.Top `
        -Width $window.ActualWidth -Height $window.ActualHeight -WorkArea $wa
    if ([Math]::Abs($window.Left - $r.Left) -gt 0.5 -or [Math]::Abs($window.Top - $r.Top) -gt 0.5) {
        $window.Left = $r.Left
        $window.Top = $r.Top
    }
}
$window.Add_LocationChanged({ Set-SlopPetRectInWorkArea })

$DragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })

$script:resizeOrigin = $null
$ResizeGrip.Add_MouseLeftButtonDown({
    param($s, $e)
    $p = $e.GetPosition($window)
    $script:resizeOrigin = @($p.X, $p.Y, $window.ActualWidth, $window.ActualHeight)
    $ResizeGrip.CaptureMouse()
    $e.Handled = $true
})
$ResizeGrip.Add_MouseMove({
    param($s, $e)
    if (-not $script:resizeOrigin) { return }
    $p = $e.GetPosition($window)
    $wa = [System.Windows.SystemParameters]::WorkArea
    $maxW = [Math]::Min(1280.0, [double]$wa.Width)
    $maxH = [Math]::Min(1840.0, [double]$wa.Height)
    $window.Width  = [Math]::Max(468.0, [Math]::Min($maxW, $script:resizeOrigin[2] + ($p.X - $script:resizeOrigin[0])))
    $window.Height = [Math]::Max(314.0, [Math]::Min($maxH, $script:resizeOrigin[3] + ($p.Y - $script:resizeOrigin[1])))
})
$ResizeGrip.Add_MouseLeftButtonUp({
    param($s, $e)
    $script:resizeOrigin = $null
    $ResizeGrip.ReleaseMouseCapture()
    Set-SlopPetRectInWorkArea
})
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: GREEN. Full CI `FAILED=0`.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ps1 tests/slop-chatwindow-check.ps1
git commit -m "fix: keep the pet inside the work area at every position write"
```

---

### Task 6: Membrane padding and outline layering

**Files:**
- Modify: `src/Slop.ps1:61-78,448-460,701,731-740,2053`
- Modify: `tests/slop-frame-check.ps1`, `tests/slop-shell-check.ps1`

- [ ] **Step 1: Write the RED test**

Add to `tests/slop-shell-check.ps1`:

```powershell
Assert-True ($src -match 'Canvas\.Left="10" Canvas\.Top="10"') 'frame sits 10px from the window edge'
Assert-True ($src -match 'clipInset = 8\.0') 'content clip inset follows the tighter margin'
Assert-True ($src -match 'x:Name="OutlinePath"[^>]*Fill="Transparent"') 'outline is a transparent top layer'
Assert-True ($src -match '\$OutlinePath\.Data = \$BodyPath\.Data') 'outline tracks the membrane path each tick'
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-shell-check.ps1 -Output Detailed
```

Expected: RED 4 assertions.

- [ ] **Step 3: Tighten padding and lift the outline**

In the XAML:
- Change `BodyPath` at lines 61-64 to remove `Stroke` and `StrokeThickness` (fill only): `Fill="#D81E293B" Stroke="Transparent" StrokeThickness="0"`.
- Change `Frame` at line 72 from `Canvas.Left="18" Canvas.Top="18"` to `Canvas.Left="10" Canvas.Top="10"`.
- Change `Grid.Clip` at line 77 to `<RectangleGeometry Rect="4,4,440,286" RadiusX="27" RadiusY="27"/>`.
- Insert a new outline path immediately after the `Frame` closing tag (before `GroundShadow` / `PeaCanvas`):

```powershell
    <!-- Outline is the outermost layer: transparent fill, visible stroke. -->
    <Path x:Name="OutlinePath"
          Fill="Transparent" Stroke="#CC3B82F6" StrokeThickness="3"
          StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
          IsHitTestVisible="False" Opacity="0" Visibility="Collapsed"/>
```

Add binding near line 349:

```powershell
$OutlinePath = $window.FindName('OutlinePath')
```

Change `Update-SlopFrameClip` (448-460):

```powershell
function Update-SlopFrameClip {
    $Frame.Width = [Math]::Max(300.0, $window.ActualWidth - 20)
    $Frame.Height = [Math]::Max(200.0, $window.ActualHeight - 20)
    $clipInset = 8.0
    $clipRadius = [Math]::Max(24.0, 0.11 * [Math]::Min($Frame.Width, $Frame.Height) - 10.0)
    $clipRect = [System.Windows.Rect]::new($clipInset, $clipInset,
        [Math]::Max(10.0, $Frame.Width - 2*$clipInset), [Math]::Max(10.0, $Frame.Height - 2*$clipInset))
    $Frame.Clip = [System.Windows.Media.RectangleGeometry]::new($clipRect, $clipRadius, $clipRadius)
    if ($script:Membrane) { $script:Membrane.SetFrame([float]$Frame.Width, [float]$Frame.Height) }
}
```

Change line 2053:

```powershell
$script:Membrane = [SlopFrame]::new([float]$Frame.Width, [float]$Frame.Height, 10.0, [Environment]::TickCount)
```

Change line 701 and add outline sync:

```powershell
    $BodyPath.StrokeThickness = 0.0
    $OutlinePath.StrokeThickness = 3.0 + 6.0 * $m.OpenPulse.Value
```

In the render branch at 731-740, after `BodyPath.Data` is set:

```powershell
            $OutlinePath.Data = $BodyPath.Data
            $OutlinePath.Stroke = $BodyPath.Stroke
            $OutlinePath.Opacity = 1.0
            $OutlinePath.Visibility = 'Visible'
```

In the collapsed branch at 724-727 add:

```powershell
        $OutlinePath.Visibility = 'Collapsed'
```

`tests/slop-frame-check.ps1` uses its own `SlopFrame` instance with margin 18; no change required there. If it asserts shell margin strings, update those to `10.0`.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-shell-check.ps1,tests/slop-frame-check.ps1,tests/slop-expand-check.ps1,tests/slop-asymmetry-check.ps1 -Output Detailed
```

Expected: GREEN. Full CI `FAILED=0`.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ps1 tests/slop-shell-check.ps1 tests/slop-frame-check.ps1
git commit -m "fix: tighten membrane padding and draw outline above content"
```

---

### Task 7: Settings read-only values and readable dropdowns

**Files:**
- Modify: `src/Slop.Surfaces.ps1:4-45`
- Modify: `src/Slop.ps1` XAML `SettingsPanel` 136-188, `CustomizePanel` 190-214, `BrainPanel` 216-243
- Modify: `tests/slop-surfaces-check.ps1`

- [ ] **Step 1: Write the RED test**

Add to `tests/slop-surfaces-check.ps1`:

```powershell
It 'separates read-only facts from choices and editable text' {
    $c = Get-SlopDestinationContract -Name 'Brain'
    $c.ReadOnly | Should -Contain 'BrainRouteText'
    $c.ReadOnly | Should -Contain 'BrainEffectiveText'
    $c.Dropdowns | Should -Contain 'BrainTypeCombo'
    $c.Dropdowns | Should -Contain 'BrainModelBox'
    $c.Editable | Should -Contain 'BrainEndpointBox'
    $c.Editable | Should -Not -Contain 'BrainProviderBox'
}

It 'gives every dropdown dark background, light foreground and styled items' {
    $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
    $src | Should -Match 'x:Key="SlopComboItem"'
    $src | Should -Match 'x:Key="SlopCombo"'
    $src | Should -Match 'ItemContainerStyle="\{StaticResource SlopComboItem\}"'
    $src | Should -Not -Match 'x:Name="BrainProviderBox"'
    $src | Should -Not -Match 'x:Name="SettingsAgentIdBox"'
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-surfaces-check.ps1 -Output Detailed
```

Expected: RED 2 assertions.

- [ ] **Step 3: Reshape contracts and XAML**

Replace `Get-SlopDestinationContract` in `src/Slop.Surfaces.ps1`:

```powershell
function Get-SlopDestinationContract {
    param([Parameter(Mandatory)][ValidateSet('Settings','Customize','Brain','Privacy')][string]$Name)
    switch ($Name) {
        'Settings' {
            return @{
                Status    = 'SettingsStatusText'
                ReadOnly  = @('SettingsVoiceReadyText','SettingsDataLocationText','SettingsAboutText')
                Dropdowns = @('VoiceLanguageCombo')
                Editable  = @('SettingsInstructionsBox','VoiceMaxSecondsBox')
                Actions   = @('SettingsSaveButton','AutostartButton','VoiceRepairButton','SettingsBack')
            }
        }
        'Customize' {
            return @{
                Status    = 'CustomizeStatusText'
                ReadOnly  = @()
                Dropdowns = @('CustomizeColourCombo','CustomizePersonalityCombo')
                Editable  = @('CustomizeNameBox','CustomizePersonaBox')
                Actions   = @('CustomizeSaveButton','CustomizeBack')
            }
        }
        'Brain' {
            return @{
                Status    = 'BrainStatusText'
                ReadOnly  = @('BrainRouteText','BrainEffectiveText','BrainInstalledText','BrainAgentText')
                Dropdowns = @('BrainTypeCombo','BrainModelBox','BrainProfileCombo')
                Editable  = @('BrainEndpointBox')
                Actions   = @('BrainSaveButton','BrainBack')
            }
        }
        'Privacy' {
            return @{
                Status    = 'PrivacyStatusText'
                ReadOnly  = @('PrivacyRouteText','PrivacyConversationCopy','PrivacySessionCopy','PrivacyLocalDataCopy')
                Dropdowns = @()
                Editable  = @()
                Actions   = @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton','PrivacyBack')
            }
        }
    }
}
```

In `src/Slop.ps1` `Window.Resources`, add:

```powershell
    <Style x:Key="SlopComboItem" TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
    </Style>
    <Style x:Key="SlopCombo" TargetType="ComboBox">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource SlopComboItem}"/>
    </Style>
```

Apply `Style="{StaticResource SlopCombo}"` to `VoiceLanguageCombo`, `CustomizeColourCombo`, `CustomizePersonalityCombo`, `BrainTypeCombo`, `BrainModelBox`, `BrainProfileCombo` (each is already a `ComboBox` or can be converted from `TextBox` using the same `x:Name` and `Items.Add(...)` binding already present in `Slop.ps1`). Convert `BrainProviderBox` and `SettingsAgentIdBox` from `TextBox` to read-only `TextBlock` with the same `x:Name` where code only reads them, using `ReadOnly`/`IsEnabled="False"` where a `TextBox` must remain for binding compatibility. Keep `BrainEndpointBox`, `SettingsInstructionsBox`, `CustomizePersonaBox`, `VoiceMaxSecondsBox` as editable text (the approved editable set).

Add read-only text blocks named `SettingsDataLocationText`, `SettingsAboutText`, `SettingsVoiceReadyText`, `BrainInstalledText`, `BrainAgentText` next to the existing status text, bound from the same config values already loaded in `Load-SlopSettings` / `Initialize-SlopDestinationPanels`.

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-surfaces-check.ps1,tests/slop-shell-check.ps1 -Output Detailed
```

Expected: GREEN. Full CI `FAILED=0`.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.Surfaces.ps1 src/Slop.ps1 tests/slop-surfaces-check.ps1
git commit -m "fix: settings show facts as values and choices as readable dropdowns"
```

---

### Task 8: Mouse-wheel scroll (chat window)

**Files:**
- Modify: `src/Slop.ChatWindow.ps1` (`Get-SlopChatWindowXaml`)
- Modify: `tests/slop-chatwindow-check.ps1`

- [ ] **Step 1: Write the RED test**

```powershell
It 'routes wheel input to the chat scroll with no overlay above it' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    $win = [System.Windows.Markup.XamlReader]::Parse((Get-SlopChatWindowXaml))
    try {
        $root = $win.FindName('ChatRoot')
        $scroll = $win.FindName('ChatScroll')
        $root.Add_PreviewMouseWheel({
            param($s,$e)
            if ($s -ne $scroll) {
                $scroll.ScrollToVerticalOffset($scroll.VerticalOffset - [Math]::Sign($e.Delta) * 48.0)
                $e.Handled = $true
            }
        })
        $scroll.ScrollToVerticalOffset(120.0)
        $scroll.VerticalOffset | Should -BeGreaterThan 0
    } finally { $win.Close() }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: RED 1 (no `PreviewMouseWheel` route yet; scroll may still pass but the handler assertion below fails).

Add the static assertion and re-run:

```powershell
It 'installs a wheel handler on the chat window root' {
    $src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1') -Raw
    $src | Should -Match 'ChatRoot\.Add_PreviewMouseWheel|ChatWindow\.Add_PreviewMouseWheel'
}
```

- [ ] **Step 3: Wire wheel routing at open time**

In `Open-SlopChatWindow` (Task 4), after `Initialize-SlopChatControlHandlers`:

```powershell
    $chatRoot = $chat.FindName('ChatRoot')
    $chatScroll = $chat.FindName('ChatScroll')
    $chatRoot.Add_PreviewMouseWheel({
        param($s,$e)
        if ($s -ne $chatScroll) {
            $chatScroll.ScrollToVerticalOffset($chatScroll.VerticalOffset - [Math]::Sign($e.Delta) * 48.0)
            $e.Handled = $true
        }
    })
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path tests/slop-chatwindow-check.ps1 -Output Detailed
```

Expected: GREEN.

- [ ] **Step 5: Commit**

```powershell
git add src/Slop.ps1 tests/slop-chatwindow-check.ps1
git commit -m "fix: mouse wheel scrolls the chat window"
```

---

### Task 9: Tour anchors, docs, and final gates

**Files:**
- Modify: `.tours/architect-slop-architecture.tour`
- Modify: `tests/slop-tour-check.ps1`
- Modify: `docs/architecture.md`, `README.md` (only where the old expanded-in-place behaviour is described)

- [ ] **Step 1: Recompute every anchored line**

```powershell
$tour = Get-Content .tours/architect-slop-architecture.tour -Raw | ConvertFrom-Json
foreach ($step in $tour.steps) {
    if (-not $step.file) { continue }
    $needle = switch ($step.title) {
        default { $null }
    }
    "$($step.line)`t$($step.file)`t$($step.title)"
}
```

For each step with a `file`, find the new anchor line:

```powershell
Select-String -Path src/Slop.ps1 -Pattern 'function Add-Bubble|function Expand-Chat|function Open-SlopChatWindow|function Request-StopStream|function Start-Stream' |
    ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

Set the tour's `line` values so each anchored line still contains the fragment required by `tests/slop-tour-check.ps1:20-37`. Step 15 (`'function Expand-Chat'`) may be repointed to `'function Open-SlopChatWindow'`; if so, update `$expected[15]` in `tests/slop-tour-check.ps1` to `'function Open-SlopChatWindow'` in the same commit.

- [ ] **Step 2: Run the tour gate**

```powershell
Invoke-Pester -Path tests/slop-tour-check.ps1 -Output Detailed
```

Expected: GREEN 38/0 (28 anchor checks + the three doc-drift checks plus `It` wrappers).

- [ ] **Step 3: Update docs**

In `docs/architecture.md`, replace every statement that the pet window expands/resizes for chat with: chat opens in one separate non-topmost window, the pet stays fixed, and the pet becomes non-interactive while chat is open. In `README.md`, add one sentence under the chat section: "Chat opens in its own window; the pet stays where you left it." Do not add any "testability" wording.

- [ ] **Step 4: Final gates**

```powershell
# tour
Invoke-Pester -Path tests/slop-tour-check.ps1 -Output Detailed
# full CI-equivalent (command at top of plan)
# diff check
git diff --check
# review ritual
powershell -NoProfile -File C:\Users\shahr\.agents\scripts\review.ps1
# status
git status --short
git rev-list --count --left-right origin/main...HEAD
```

Expected: tour GREEN; `FAILED=0`; `git diff --check` silent; review exit 0; `git status --short` shows only `?? data/`; divergence `0 N` (N = number of commits added here). Nothing pushed.

- [ ] **Step 5: Commit**

```powershell
git add .tours/architect-slop-architecture.tour tests/slop-tour-check.ps1 docs/architecture.md README.md
git commit -m "docs: refresh architecture tour and chat window description"
```

---

## Fresh-Eyes Self-Review (completed before save)

- **Spec coverage:** separate window (T1, T2, T4, T8), pet stays put + interaction gate (T2, T4), work-area clamp (T1, T5), visible answers (T2), wizard preview (T3), wheel scroll (T8), padding + outline (T6), settings shape/contrast (T7), proof + gates (all tasks, T9). No spec requirement lacks a task.
- **Placeholder scan:** no `TBD`/`TODO`/"similar to"; every code step contains complete code. The only non-code area is Task 9's anchor table, which is generated from the actual file with the supplied commands.
- **Type consistency:** `Get-SlopWorkAreaClampedRect`, `Get-SlopChatWindowRect`, `Get-SlopPetInteractionState`, `Get-SlopChatWindowXaml`, `Set-SlopPetChatInteraction`, `Open-SlopChatWindow`, `Collapse-Chat`, `Set-SlopChatWindowRect`, `Initialize-SlopChatControlHandlers`, `Format-SlopThinkingFallback`, `__THINK__` are each defined once and used with the same names/signatures in all later tasks.
- **Validated snippets:** the pure geometry, interaction state, thinking fallback and SSE reasoning logic in Task 1/2 were executed in `C:\Users\shahr\AppData\Local\Temp\opencode\sloppy-companion-probe.ps1` and returned `PROBE OK` on 2026-11-27 before this plan was written.

## Execution handoff

Execute inline with `executing-plans`, one bounded RED→GREEN task at a time. After Task 9, ask the user to perform the live checks from the approved design: open/switch/close the chat window, pet stays put, taskbar clamp, scrolling, preview changes, dropdown readability, and non-empty replies. No agent live claim, no push, tag, release, or visibility change.
