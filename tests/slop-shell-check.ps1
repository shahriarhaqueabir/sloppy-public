# tests/slop-shell-check.ps1
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$script:SlopChecks = [System.Collections.Generic.List[object]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:SlopChecks.Add([pscustomobject]@{ Name = $Message; Passed = [bool]$Condition })
}
function Find-AncestorByName {
    param([System.Windows.DependencyObject]$Element, [string]$Name)
    $current = $Element
    while ($null -ne $current) {
        if ($current -is [System.Windows.FrameworkElement] -and $current.Name -eq $Name) { return $current }
        $current = [System.Windows.LogicalTreeHelper]::GetParent($current)
    }
    return $null
}

$src = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
$m = [regex]::Match($src, '\$xaml = @''\r?\n(?<xaml>.*?)\r?\n''@', 'Singleline')
Assert-True $m.Success 'XAML here-string found'
if ($m.Success) {
    $w = [System.Windows.Markup.XamlReader]::Parse($m.Groups['xaml'].Value)
    foreach ($name in @('BodyPath','HeadHighlight','Frame','SettingsDot','PinDot','CloseDot','ControlDots','ChatScroll','ChatStack','InputBox','MicBtn','StatusDot','ResizeGrip','PeaCanvas','GroundShadow','ShortcutsStrip','RouteBadge','VoiceEnabledCheck','VoiceLanguageCombo','VoiceMaxSecondsBox','VoiceRepairButton','VoiceReadyText')) {
        Assert-True ($null -ne $w.FindName($name)) "XAML element $name exists"
    }
    # Four quiet destinations: each panel and its read-only views must exist.
    foreach ($name in @('SettingsPanel','CustomizePanel','BrainPanel','PrivacyPanel','AdvancedStack',
                        'PrivacyRouteText','PrivacyTermsLink','PrivacyConversationCopy','PrivacySessionCopy','PrivacyLocalDataCopy')) {
        Assert-True ($null -ne $w.FindName($name)) "XAML element $name exists"
    }
    foreach ($name in @(
        'SettingsStatusText','CustomizeStatusText','BrainStatusText','PrivacyStatusText',
        'CustomizeNameBox','CustomizeColourCombo','CustomizePersonalityCombo','CustomizePersonaBox','CustomizeSaveButton',
        'BrainTypeCombo','BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo','BrainSaveButton'
    )) {
        Assert-True ($null -ne $w.FindName($name)) "XAML element $name exists"
    }
    foreach ($id in @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton')) {
        $el = $w.FindName($id)
        Assert-True ($null -ne $el) "deletion button $id exists"
        if ($el) {
            Assert-True ($null -ne (Find-AncestorByName $el 'PrivacyPanel')) "$id is owned by Privacy"
            Assert-True ($null -eq (Find-AncestorByName $el 'SettingsPanel')) "$id is not owned by Settings"
        }
    }
    Assert-True ($src -match 'function Set-SlopDestinationStatus') 'visible per-page status helper exists'
    Assert-True ($src -match 'Get-SlopDestinationContract -Name \$Name') 'status helper resolves IDs from the contract map'
    Assert-True ($src -match 'Set-SlopDestinationStatus -Name \$Name -Text') 'opening a destination clears its status'
    Assert-True ($src -match 'function Update-SlopIdentityFromConfig') 'identity refresh has a reusable helper'
    Assert-True ($src -match 'Get-SlopEffectiveOpenCodeBaseUrl[\s\S]{0,400}Update-SlopIdentityFromConfig') 'identity refresh is called at startup'
    Assert-True ($src -match 'function Save-SlopCustomize') 'Customize has a save handler'
    Assert-True ($src -match 'function Save-SlopBrain') 'Brain has a save handler'
    Assert-True ($src -match 'Set-SlopConfigIdentity[\s\S]{0,80}\$script:SlopConfigResult\.Config') 'Customize validates through the pure identity helper'
    Assert-True ($src -match 'Set-SlopConfigBrain[\s\S]{0,80}\$script:SlopConfigResult\.Config') 'Brain validates through the pure brain helper'
    Assert-True ($src -match 'function Save-SlopSettings[\s\S]{0,2400}Set-SlopDestinationStatus -Name Settings -Text ''Settings saved\.''') 'Settings reports success on its own page'
    Assert-True ($src -notmatch "Add-SlopThoughtBubble -Text 'Settings saved\.'") 'Settings no longer reports into hidden chat'
    Assert-True ($src -match 'function Invoke-SlopDeletion[\s\S]{0,900}Set-SlopDestinationStatus -Name Privacy') 'deletion reports on the Privacy page'
    Assert-True ($w.FindName('RouteBadge').Text -match 'Qwen3\.5-2B Q4_K_M') 'route badge discloses the bundled model from first frame'
    Assert-True ($src -notmatch 'Set-SlopRouteBadge\s+-Kind\s') 'config badge updater does not call the removed Kind signature'
    Assert-True ($src -match 'Set-SlopRouteBadge -StreamPlan \$badgePlan') 'config badge updater passes a stream plan'
    Assert-True ($src -match 'Badge=\(Get-SlopRouteBadge -Kind \$kind -Provider \$provider -Model \$effective\)') 'config badge plan resolves the honest route label'
    Assert-True ($src -match '\$MicBtn = \$window\.FindName\(''MicBtn''\)') 'mic button is bound from XAML before handlers are registered'
    Assert-True ($src -notmatch 'AttachBtn') 'text-only composer has no attach affordance'
    # BrushConverter returns a Brush; SolidColorBrush::new needs a Color. A missed
    # `.Color` crashed ShowDialog in the live verifier, so guard it statically too.
    Assert-True ($src -match 'IdentityBrush = \[System\.Windows\.Media\.SolidColorBrush\]::new\(\s*\[System\.Windows\.Media\.BrushConverter\]::new\(\)\.ConvertFromString\([\s\S]*?\)\.Color\)') 'identity brush converts to Color before constructing SolidColorBrush'
    # Live verification caught a real wiring gap: the route plan reported that the
    # bundled brain needed starting, but no worker ever started it, so the first
    # send was refused by port 18080. Guard all three links in that chain.
    Assert-True ($src -match 'Get-SlopStreamPlan[\s\S]{0,240}-LocalModelProcess \$script:LocalModelProcess') 'stream plan receives the already-owned local model process'
    Assert-True ($src -match 'Start-ThreadJob[\s\S]{0,1400}Start-SlopLocalModel -Paths \$Plan\.LocalModelPaths -ContextSize \(\[int\]\$Plan\.LocalModelContextSize\)') 'adapter worker wakes the bundled brain with configured context size'
    Assert-True ($src -match "tok\.StartsWith\('__SLOPMODEL__'\)") 'UI thread records the worker-started model process for clean shutdown'
    $verifier = Get-Content (Join-Path $PSScriptRoot '../tools/verify-motion.ps1') -Raw
    Assert-True ($verifier -match 'function Wait-DotBlue') 'live verifier waits for the header dot fade after expand'
    Assert-True ($verifier -match 'if \(Get-ChatWin\) \{ \$expanded = \$true') 'chat opening is detected by window presence'
    Assert-True ($verifier -notmatch 'Wait-DotBlue -TimeoutMs 45000') 'chat opening no longer samples a hidden pet status dot'
    Assert-True ($verifier -match 'for \(\$i=0; \$i -lt 400; \$i\+\+\)[\s\S]{0,200}\$chatAfter = Get-ChatText') 'send poll waits for rendered chat text through slow local brain startup'
    Assert-True ($verifier -match 'function Set-UiaCombo') 'live verifier can select ComboBox items'
    Assert-True ($verifier -match 'Set-UiaValue ''SettingsAgentIdBox'' ''probe-agent''') 'live verifier edits Settings'
    Assert-True ($verifier -match 'Set-UiaCombo ''CustomizeColourCombo'' ''plum''') 'live verifier edits Customize'
    Assert-True ($verifier -match 'Set-UiaCombo ''BrainTypeCombo'' ''opencode''') 'live verifier edits Brain'
    Assert-True ($verifier -match 'Get-UiaText ''PrivacyRouteText''') 'live verifier reads the Privacy route after a Brain save'
    Assert-True ($verifier -match 'function Grab \{[\s\S]{0,900}\$script:LastGrabRect = \$r') 'capture stores one window rect per grab'
    Assert-True ($verifier -match 'function Pixel\(\$b,\$lx,\$ly\) \{[\s\S]{0,300}\$script:LastGrabRect') 'pixel lookup uses the same rect as its bitmap'
    Assert-True ($verifier -match 'function Grab \{[\s\S]{0,300}Get-Win \$proc\.Id') 'capture re-queries the top-level window before reading its rect'
    Assert-True ($verifier -match 'function Get-AppWindows') 'live verifier enumerates every top-level window in the app process'
    Assert-True ($verifier -match 'function Get-ChatWin') 'live verifier resolves the separate chat window by title'
    Assert-True ($verifier -match 'function Find-UiaIn') 'live verifier can scope an automation search to one window'
    Assert-True ($verifier -match 'Invoke-UiaIn \(Get-ChatWin\) ''ChatModeButton''') 'live verifier toggles chat size in the chat window'
    Assert-True ($verifier -match 'CHAT Extended size=') 'live verifier checks the Extended chat geometry'
    Assert-True ($verifier -match 'CHAT Full size=') 'live verifier checks the Full work-area chat geometry'
    Assert-True ($verifier -match 'CHAT closed pet=') 'live verifier proves the pet keeps its size after chat closes'
    Assert-True ($verifier -notmatch 'Invoke-Uia ''SettingsDot''') 'live verifier no longer pseudo-maximizes the pet window'
    Assert-True ($verifier -notmatch 'expanded size is not 760x540') 'live verifier no longer expects the pet to expand into chat'
    $controls = $w.FindName('ControlDots')
    Assert-True ($controls -is [System.Windows.Controls.Border]) 'control actions are grouped in a separate glass tile'
    if ($controls -is [System.Windows.Controls.Border]) {
        Assert-True ($controls.HorizontalAlignment -eq [System.Windows.HorizontalAlignment]::Right) 'control tile sits at the right edge of the header'
        Assert-True ($controls.CornerRadius.TopLeft -ge 8) 'control tile uses the shared rounded surface language'
        Assert-True ($controls.BorderThickness.Left -gt 0) 'control tile has a visible rim'
    }
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
    $inputTile = $w.FindName('InputTile')
    Assert-True ($inputTile -is [System.Windows.Controls.Border]) 'message composer has its own glass tile'
    if ($inputTile -is [System.Windows.Controls.Border]) {
        Assert-True ($inputTile.BorderThickness.Left -gt 0) 'message composer tile has a visible rim'
        Assert-True ($inputTile.CornerRadius.TopLeft -eq 14) 'message composer uses the shared 14px tile radius'
    }
    $pea = $w.FindName('PeaCanvas')
    $shadow = $w.FindName('GroundShadow')
    if ($pea -and $shadow) {
        Assert-True ([System.Windows.Controls.Canvas]::GetLeft($pea) + $pea.Width -le $w.Width) 'idle pea fits inside the window horizontally'
        Assert-True ([System.Windows.Controls.Canvas]::GetTop($pea) + $pea.Height -le $w.Height) 'idle pea fits inside the window vertically'
        Assert-True ([System.Windows.Controls.Canvas]::GetLeft($shadow) + $shadow.Width -le $w.Width) 'ground shadow fits inside the window horizontally'
        Assert-True ([System.Windows.Controls.Canvas]::GetTop($shadow) + $shadow.Height -le $w.Height) 'ground shadow fits inside the window vertically'
    }
    $bodyPath = $w.FindName('BodyPath')
    if ($bodyPath) {
        Assert-True ([double]::IsNaN([System.Windows.Controls.Canvas]::GetLeft($bodyPath))) 'body path uses window-space coordinates'
        Assert-True ([double]::IsNaN([System.Windows.Controls.Canvas]::GetTop($bodyPath))) 'body path has no top offset'
    }
}
Assert-True ($src -notmatch '\$Frame\.RenderTransform\s*=') 'content frame is never transformed by motion'
Assert-True ($src -match 'Slop\.Frame\.ps1') 'membrane engine module is dot-sourced'
Assert-True ($src -match '\[SlopFrame\]::new') 'membrane engine is instantiated by the shell'
Assert-True ($src -notmatch '\$script:Frame\s*=') 'engine variable does not shadow the XAML Frame grid'
Assert-True ($src -match '\$script:Membrane\.Update') 'membrane physics runs on the motion clock'
Assert-True ($src -match '\$BodyPath\.Data\s*=') 'body path data is written each tick'
Assert-True ($src -match '\$HeadHighlight\.Data\s*=') 'rim highlight follows the outline'
Assert-True ($src -match '\$Frame\.Clip\s*=') 'content clip is rebuilt on resize'
Assert-True ($src -match 'Add_SizeChanged(?s:.*?)Update-SlopFrameClip') 'clip/layout rebuild lives in the SizeChanged handler'
Assert-True ($src -notmatch 'MaxHeight="235"') 'chat scroll is not height-capped'
Assert-True ($src -match 'function Open-SlopChatWindow') 'chat opens in its own window'
Assert-True ($src -match 'Set-SlopPetChatInteraction -ChatOpen \$false') 'pet interaction is restored after chat closes'
Assert-True ($src -match '\$script:ChatWindow\.Activate\(\)') 'an existing chat window is brought to front'
Assert-True ($src -match '\$script:ChatWindow\.Add_Closed') 'chat close restores the pet surface'
Assert-True ($src -match 'SetMotionScale') 'reduced motion is forwarded to the membrane'
Assert-True ($src -notmatch 'EdgeMode="Aliased"') 'smooth vector curves are not aliased'
Assert-True ($src -match 'StrokeLineJoin="Round"') 'body outline uses round joins'
Assert-True ($src -match 'Add_SizeChanged') 'window size changes relayout the organic body'
Assert-True ($src -match '\$script:Membrane\.SetFrame') 'window resizes are forwarded to the membrane'
Assert-True ($src -match 'function Update-PeaAnchor') 'pea anchor has a dedicated layout function'
Assert-True ($src -match 'Update-PeaAnchor\s*\r?\n') 'pea anchor is called to set the initial position'
Assert-True ($src -match 'Add_SizeChanged(?s:.*?)Update-PeaAnchor') 'pea anchor follows window resizes'
Assert-True ($src -match '\$ResizeGrip\.Add_MouseMove') 'resize grip has a live drag handler'
Assert-True ($src -match 'function Insert-SlopShortcut') 'shortcut chips only insert text, never execute'
Assert-True ($src -match "startslop.*stopslop.*slopstatus") 'profile helper shortcuts are present'
Assert-True ($src -match "Add-Bubble|function Add-Bubble") 'bubble renderer exists'
Assert-True ($src -match 'AllowEmptyString\(\)\]\[string\]\$Text') 'streaming placeholder can start with empty bubble text'
Assert-True ($src -match '(?m)^#requires -Version 7\.6') 'entry point declares the PowerShell floor'
Assert-True ($src -match '\$clipInset = 14\.0') 'content clip uses a 14px inset for rounded-corner safety'
Assert-True ($src -match '\$clipRadius = \[Math\]::Max\(24\.0, 0\.11') 'content clip radius tracks the body corner radius with safety margin'
Assert-True ($src -match 'function Update-SlopFrameClip') 'frame clip/layout updates through a dedicated function'
Assert-True ($src -match '\$this\.IsEnabled = \$false') 'approval buttons ignore a rapid second click'
Assert-True ($src -notmatch 'llama\.cpp Pal') 'stale llama.cpp product description is gone'

Assert-True ($src -notmatch "Did you know: honey never spoils") 'canned trivia is removed'
Assert-True ($src -match '\$fontSize = 8') 'bubbles use the compact 8px font on the pet surface'
Assert-True ($src -match "TextWrapping = 'Wrap'") 'bubble text wraps instead of clipping'

Assert-True ($src -match 'Slop\.Sense\.ps1') 'System Sense module is dot-sourced'
Assert-True ($src -match 'System Sense: On') 'tray toggle is wired'
Assert-True ($src -match 'SenseAccumulator -ge 60\.0') 'sense runs once a minute'
Assert-True ($src -match 'MotionIntervalMs = 33') 'adaptive motion interval starts at the full 33 ms rate'
Assert-True ($src -match 'Get-SlopMotionIntervalMs') 'timer selects cadence through the pure helper'
Assert-True ($src -match 'MotionTimer\.Interval = \[TimeSpan\]::FromMilliseconds\(\$wantMs\)') 'timer interval is reassigned only when cadence changes'
Assert-True (([regex]::Matches($src, '\$PeaCanvas\.RenderTransform\s*=')).Count -eq 1) 'pea transform is assigned once at initialization'
Assert-True (([regex]::Matches($src, '\$GroundShadow\.RenderTransform\s*=')).Count -eq 1) 'shadow transform is assigned once at initialization'
Assert-True ($src -match '\$script:PeaTranslate\.X\s*=') 'pea transform X updates in place'
Assert-True ($src -match '\$script:ShadowScaleTransform\.ScaleX\s*=') 'shadow scale updates in place'
Assert-True ($src -match '\$bodyClosed = \$script:Membrane\.IsClosed') 'collapsed state is sampled once per tick'
Assert-True ($src -match 'if \(-not \$bodyClosed\) \{\s*\$script:Membrane\.Update') 'membrane physics is skipped while collapsed'
Assert-True ($src -match 'if \(-not \$bodyClosed\) \{\s*\$BodyPath\.Data') 'outline geometry is not rebuilt while collapsed'
Assert-True ($src -match "ChatMode -eq 'Full'") 'full chat mode is tracked separately from the pet'
Assert-True ($src -match '\[System\.Windows\.SystemParameters\]::WorkArea') 'chat window sizes to the work area'
Assert-True ($src -notmatch "WindowState\s*=\s*'Maximized'") 'shell no longer toggles true maximize'
Assert-True ($src -match 'Get-SlopChatWindowRect') 'chat geometry is computed by the pure contract'
Assert-True ($src -match '\$pattern = switch -Exact \(\$sig\.Kind\)') 'face tick chooses a pattern from effective signal before drawing'
Assert-True ($src -match '\$sig = Get-SlopSignal -State \$script:Motion') 'face tick resolves the effective signal explicitly'
Assert-True ($src -match '\$sig\.Kind -in @\(''approval'',''stalled'',''warning'',''thinking'',''error'',''critical''\)') 'attention/error kinds drive the frozen face state'
Assert-True ($src -match '0\.3 \+ 1\.7 \* \$script:Motion\.MoodPulse\.Value') 'success face speed follows the mood pulse'
Assert-True ($src -notmatch 'Update-SlopFaceLayer[^\r\n]*-Pattern \$script:Motion\.FaceExpression') 'face pattern is chosen, not passed straight from the idle action'
Assert-True ($src -notmatch 'ThoughtAccumulator') 'old random thought timer is gone'
Assert-True ($src -match 'function Update-SlopFaceRegion') 'face region has a dedicated layout function'
Assert-True ($src -match '\$Stage\.Children\.Insert\(\$idx, \$layer\)') 'face layer is inserted before the Frame in z-order'
Assert-True ($src -match 'System\.Windows\.Rect\]::new\(0\.0, 0\.0, \$w, \$h\), 12\.0, 12\.0') 'compact face region uses a rounded clip'
Assert-True ($src -notmatch '\$layer\.Clip = \$BodyPath\.Data') 'pet face never clips to an expanded membrane path'
Assert-True ($src -match '\$script:FaceRegion\.Width') 'motion tick uses the computed face region size'
Assert-True ($src -match '-Inset 3\.0') 'motion tick passes the configured inset'

Assert-True ($src -match '\$x = if \(\$script:ReducedMotion\) \{ 0\.0 \}') 'reduced motion zeroes the pea sway'
Assert-True ($src -match 'if \(\$script:ReducedMotion\) \{\s*\$frozen = \$true;\s*\$speed = 0\.0\s*\}') 'reduced motion freezes the particle field'

Assert-True ($src -match '\$BodyPath\.StrokeThickness = 3\.0 \+ 6\.0 \* \$m\.OpenPulse\.Value') 'OpenPulse drives the body outline thickness'
Assert-True ($src -match '\$HeadHighlight\.Opacity = \[Math\]::Min\(1\.0, 0\.55 \+ 0\.10 \* \$m\.OpenPulse\.Value\)') 'OpenPulse modulates the rim highlight opacity'
Assert-True (([regex]::Matches($src, '\$HeadHighlight\.Opacity\s*=')).Count -eq 1) 'highlight opacity has a single writer'

Assert-True ($src -match 'Stroke="#553B82F6"') 'highlight initial stroke uses the idle palette with 0x55 alpha'
Assert-True ($src -match '\$script:HighlightBrush = \[System\.Windows\.Media\.SolidColorBrush\]::new\(\$highlightColor\)') 'highlight brush is tracked separately from ColorBrushes'
Assert-True ($src -match 'Animate-BrushTo -Brush \$script:HighlightBrush') 'highlight colour follows the effective signal'

Assert-True ($src -match '\$script:WorkArea = \[System\.Windows\.SystemParameters\]::WorkArea') 'work area is cached in script scope'
Assert-True ($src -match '\$maxLeft = \[Math\]::Max\(\$wa\.X, \$wa\.Right - \$window\.ActualWidth\)') 'wander clamps against the work area'
Assert-True ($src -match '\$window\.Left = \[Math\]::Min\(\$maxLeft') 'wander writes the clamped left position'

Assert-True ($src -match 'Slop\.Audio\.ps1') 'headless audio module is dot-sourced by the shell'
Assert-True ($src -match 'slop-preflight\.ps1') 'preflight tool is dot-sourced by the shell'
Assert-True ($src -match '\$VoiceEnabledCheck\.IsChecked = \[bool\]\$cfg\.voiceEnabled') 'Settings loads voiceEnabled from config'
Assert-True ($src -match '\$VoiceLanguageCombo\.Text = \[string\]\$cfg\.whisperLanguage') 'Settings loads whisperLanguage from config'
Assert-True ($src -match '\$VoiceMaxSecondsBox\.Text = \[string\]\$cfg\.voiceMaxSeconds') 'Settings loads voiceMaxSeconds from config'
Assert-True ($src -match '\$cfg\.voiceEnabled = \[bool\]\$VoiceEnabledCheck\.IsChecked') 'Settings saves voiceEnabled'
Assert-True ($src -match '\$cfg\.whisperLanguage = \(\[string\]\$VoiceLanguageCombo\.Text\)\.Trim\(\)\.ToLowerInvariant\(\)') 'Settings saves a normalized whisperLanguage'
Assert-True ($src -match '\[int\]::TryParse\(\[string\]\$VoiceMaxSecondsBox\.Text') 'Settings saves a validated voiceMaxSeconds'
Assert-True ($src -match 'Invoke-SlopPreflight -InstallRoot \$script:VoiceInstallRoot') 'Repair voice runs the report-only preflight'
Assert-True ($src -match 'Get-SlopVoiceReadinessText -Config \$cfg') 'Settings shows exact Whisper readiness'
Assert-True ($src -match 'Get-SlopVoiceInstallRoot -InstallRoot') 'voice install root follows the actual app root'
$iss = Get-Content (Join-Path $PSScriptRoot '../installer/Sloppy.iss') -Raw
Assert-True ($iss -match 'Filename: "\{sys\}\\wscript\.exe"') 'installed shortcut uses wscript.exe'
Assert-True ($iss -match 'Parameters: """\{app\}\\run\.vbs"""') 'installed shortcut uses the headless VBS launcher'
Assert-True ($iss -notmatch 'Filename: "\{sys\}\\pwsh\.exe"') 'installed shortcut does not launch pwsh directly'

Assert-True ($src -match 'function Start-SlopVoiceTranscription') 'voice transcription has a named worker starter'
Assert-True ($src -match 'Invoke-SlopWhisperTranscription -Paths \$Paths -WavPath \$Wav') 'voice worker invokes the local Whisper wrapper'
Assert-True ($src -match 'Start-ThreadJob -ScriptBlock \{[\s\S]{0,900}__VOICE__') 'voice job enqueues transcript markers'
Assert-True ($src -match 'Start-Stream -UserText \$tok\.Substring\(9\)') 'transcript uses the existing text send path'
Assert-True ($src -notmatch '\$MicBtn[\s\S]{0,2400}New-SlopAttachmentFromFile -Path \$script:MicRecorderPath') 'Mic stop no longer attaches the WAV'
Assert-True ($src -match '\$script:VoiceQueue = \[System\.Collections\.Concurrent\.ConcurrentQueue\[string\]\]::new\(\)') 'voice uses a dedicated dispatcher queue'
Assert-True ($src -match '\$script:MicCapTimer\.Interval = \[TimeSpan\]::FromSeconds\(\$script:VoiceMaxSeconds\)') 'hard recording cap is configured from voiceMaxSeconds'
Assert-True ($src -match 'Remove-Item -LiteralPath \$Wav -Force -ErrorAction SilentlyContinue') 'temporary WAV is deleted in the worker finally block'
Assert-True ($src -match '\$SendBtn\.IsEnabled = -not \[bool\]\$script:IsStreaming') 'voice idle state never re-enables Send during a stream'
Assert-True ($src -match "tok\.StartsWith\('__VOICE__'\)") 'voice success marker is handled before plain text'

Assert-True ($src -match 'Get-SlopBrainOrder') 'Brain combo uses the ordered tier list'
Assert-True ($src -match 'Get-SlopBrainModelOptions -Brain') 'model options come from the shared catalog'
Assert-True ($src -notmatch '\$BrainModelBox\.Text = if \(\[string\]::IsNullOrWhiteSpace') 'Brain model box no longer accepts an off-tier saved model'
Assert-True ($src -notmatch 'Tier \(1=built-in, 2=OpenCode, 3=custom\)') 'no tier-3 label remains'
Assert-True ($src -match 'Join-Path \(Split-Path \$PSScriptRoot -Parent\) ''run\.vbs''') 'autostart targets the VBS launcher'

$gitattributes = Get-Content (Join-Path $PSScriptRoot '../.gitattributes') -Raw
$noticesPath = Join-Path $PSScriptRoot '../docs/third-party-notices.md'
$readme = Get-Content (Join-Path $PSScriptRoot '../README.md') -Raw
$architecture = Get-Content (Join-Path $PSScriptRoot '../docs/architecture.md') -Raw
Assert-True ($gitattributes -match 'runtime/whisper/\*\* filter=lfs') 'Whisper runtime is tracked with Git LFS'
Assert-True ($gitattributes -match '\*\.bin filter=lfs') 'Whisper model .bin files are tracked with Git LFS'
Assert-True (Test-Path $noticesPath) 'third-party notices file exists'
if (Test-Path $noticesPath) {
    $notices = Get-Content $noticesPath -Raw
    Assert-True ($notices -match 'whisper\.cpp') 'notices name whisper.cpp'
    Assert-True ($notices -match 'MIT') 'notices record the MIT license'
    Assert-True ($notices -match '55356645c2b361a969dfd0ef2c5a50d530afd8d5') 'notices pin the small model SHA-1'
}
Assert-True ($readme -match 'opt-in push-to-talk audio is transcribed locally') 'README documents shipped local voice transcription'
Assert-True ($architecture -match 'bundled Whisper small') 'architecture documents local voice input'
Assert-True ($readme -match 'Qwen3\.5-2B Q4_K_M') 'README names the Qwen Tier 1 brain'
Assert-True ($architecture -match 'Qwen3\.5-2B Q4_K_M') 'architecture names the Qwen Tier 1 brain'
Assert-True ($gitattributes -match 'runtime/\*\*/\*\.gguf filter=lfs') 'GGUF artifacts are tracked with Git LFS'

Describe 'Slop shell / XAML static checks' {
    foreach ($check in $script:SlopChecks) {
        $name = $check.Name
        $sb = { $check.Passed | Should -BeTrue }.GetNewClosure()
        It $name $sb
    }
}
