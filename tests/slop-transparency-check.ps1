# Headless contract for the separate transparent chat window.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

Describe 'Slop transparent chat window contract' {
    BeforeAll {
        # Pester isolates file scope from It blocks: define the pure functions
        # inside BeforeAll, where the container can see them.
        . (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1')
        $script:ChatSrc = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1')
        $script:AppSrc = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../src/Slop.ps1')
    }

    It 'clamps a requested rect inside the work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopWorkAreaClampedRect -Left 1700 -Top 900 -Width 760 -Height 540 -WorkArea $wa
        $r.Left | Should -Be 1160
        $r.Top | Should -Be 500
        $r.Width | Should -Be 760
        $r.Height | Should -Be 540
    }

    It 'never produces a zero or negative extent' {
        $wa = @{ X = 0; Y = 0; Width = 800; Height = 600 }
        $r = Get-SlopWorkAreaClampedRect -Left -50 -Top -50 -Width 5000 -Height 5000 -WorkArea $wa
        $r.Left | Should -Be 0
        $r.Top | Should -Be 0
        $r.Width | Should -Be 800
        $r.Height | Should -Be 600
    }

    It 'places the extended window beside the real pet and clamps near the taskbar' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $near = Get-SlopChatWindowRect -PetLeft 100 -PetTop 100 -PetWidth 484 -PetHeight 330 -WorkArea $wa
        $near.Left | Should -Be 608
        $near.Top | Should -Be 0
        $near.Width | Should -Be 760
        $near.Height | Should -Be 540
        $far = Get-SlopChatWindowRect -PetLeft 1700 -PetTop 900 -PetWidth 484 -PetHeight 330 -WorkArea $wa
        $far.Left | Should -Be 1160
        $far.Top | Should -Be 500
    }

    It 'centres the extended window on the real pet height without overlapping it' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopChatWindowRect -PetLeft 100 -PetTop 300 -PetWidth 484 -PetHeight 330 -WorkArea $wa
        $r.Left | Should -Be 608
        $r.Top | Should -Be 195
        $r.Left | Should -BeGreaterThan 584
    }

    It 'uses the whole work area in Full mode' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopChatWindowRect -PetLeft 100 -PetTop 100 -PetWidth 484 -PetHeight 330 -WorkArea $wa -Mode Full
        $r.Left | Should -Be 0
        $r.Top | Should -Be 0
        $r.Width | Should -Be 1920
        $r.Height | Should -Be 1040
    }

    It 'requires explicit pet dimensions so chat placement cannot use a stale pea size' {
        $script:ChatSrc | Should -Match '\[Parameter\(Mandatory\)\]\[double\]\$PetWidth'
        $script:ChatSrc | Should -Match '\[Parameter\(Mandatory\)\]\[double\]\$PetHeight'
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
        $xaml | Should -Not -Match '\bMica\b|\bAcrylic\b|\bBackdrop\b|DwmSetWindowAttribute|SetWindowCompositionAttribute'
        $script:AppSrc | Should -Not -Match '\bMica\b|\bAcrylic\b|DwmSetWindowAttribute|SetWindowCompositionAttribute'
    }

    It 'uses accessible text colours in the chat window' {
        $xaml = Get-SlopChatWindowXaml
        $xaml | Should -Not -Match '8A8A96'
        $xaml | Should -Match '93A4BD'
        $xaml | Should -Not -Match 'FontSize="9"'
    }

    It 'gives the message pane a readable dark backplate inside the transparent window' {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        $win = [System.Windows.Markup.XamlReader]::Parse((Get-SlopChatWindowXaml))
        try {
            $plate = $win.FindName('ChatBackplate')
            if ($null -eq $plate) { throw 'ChatBackplate is missing from the chat XAML' }
            [System.Windows.Controls.Grid]::GetRowSpan($plate) | Should -Be 3
            $plate.Background | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            $plate.Background.Color.A | Should -BeGreaterOrEqual 0xF2
            $plate.BorderBrush | Should -BeOfType [System.Windows.Media.SolidColorBrush]
            $plate.BorderBrush.Color.A | Should -BeGreaterOrEqual 0x66
            $plate.BorderThickness.Left | Should -BeGreaterOrEqual 1.5
            $plate.SnapsToDevicePixels | Should -BeTrue
            $plate.IsHitTestVisible | Should -BeFalse
        } finally { $win.Close() }
    }

    It 'uses opaque panel fills for chat chrome and composer' {
        $xaml = Get-SlopChatWindowXaml
        $xaml | Should -Not -Match '#221E293B'
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        $win = [System.Windows.Markup.XamlReader]::Parse($xaml)
        try {
            foreach ($name in @('ChatChrome','ChatInputChrome')) {
                $el = $win.FindName($name)
                if ($null -eq $el) { throw "$name is missing from the chat XAML" }
                $el.Background.Color.A | Should -BeGreaterOrEqual 0xF2
            }
        } finally { $win.Close() }
    }

    It 'uses near-opaque raised fills for message and approval overlays' {
        $script:AppSrc | Should -Not -Match '#2AFFFFFF'
        [regex]::Matches($script:AppSrc, "ConvertFromString\('#F2263348'\)").Count | Should -BeGreaterOrEqual 2
    }

    It 'uses readable fills for the composer field and chat buttons' {
        $xaml = Get-SlopChatWindowXaml
        $xaml | Should -Not -Match '#18FFFFFF'
        $xaml | Should -Not -Match '#33BFDBFE'
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        $win = [System.Windows.Markup.XamlReader]::Parse($xaml)
        try {
            $win.FindName('InputBox').Background.Color.A | Should -BeGreaterOrEqual 0xE6
            foreach ($name in @('ChatModeButton','ChatCloseButton','MicBtn','SendBtn','StopBtn')) {
                $win.FindName($name).Background.Color.A | Should -BeGreaterOrEqual 0xE6
            }
        } finally { $win.Close() }
    }
}

Describe 'Slop shell chat-window wiring' {
    BeforeAll {
        $script:AppSrc = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../src/Slop.ps1')
    }

    It 'dot-sources the chat window module before it is used' {
        $script:AppSrc | Should -Match 'Slop\.ChatWindow\.ps1'
    }

    It 'opens one chat window, activates an existing one, and never resizes the pet' {
        $script:AppSrc | Should -Match 'function Open-SlopChatWindow'
        $script:AppSrc | Should -Match '\$script:ChatWindow\.Activate\(\)'
        $script:AppSrc | Should -Not -Match '\$window\.Width = \$script:ExpandedSize\.Width'
    }

    It 'rebinds all shared chat controls to the chat window' {
        foreach ($id in @('ChatScroll','ChatStack','ShortcutsStrip','InputBox','InputPlaceholder','MicBtn','SendBtn','StopBtn')) {
            $script:AppSrc | Should -Match "FindName\('$id'\)"
        }
    }

    It 'uses the open-chat automation name on the pet button' {
        $script:AppSrc | Should -Match 'Content="□" ToolTip="Open chat window" AutomationProperties.Name="Open chat window"'
    }

    It 'restores pet interaction when the chat closes' {
        $script:AppSrc | Should -Match 'Set-SlopPetChatInteraction -ChatOpen \$false'
        $script:AppSrc | Should -Match '\$script:ChatWindow\.Add_Closed'
    }

    It 'routes mouse wheel input through the chat window root' {
        $script:AppSrc | Should -Match 'ChatRoot\.Add_PreviewMouseWheel|ChatWindow\.Add_PreviewMouseWheel'
        $script:AppSrc | Should -Match 'ScrollToVerticalOffset\(\$chatScroll\.VerticalOffset'
    }

    It 'clamps every pet position write to the work area' {
        $script:AppSrc | Should -Match '\$window\.Add_LocationChanged'
        $script:AppSrc | Should -Match 'Get-SlopWorkAreaClampedRect -Left \$window\.Left'
        $script:AppSrc | Should -Match '\$window\.Left = \$r\.Left'
    }

    It 'passes the real pet size when positioning the chat window' {
        $script:AppSrc | Should -Match 'Get-SlopChatWindowRect[^\r\n]*-PetWidth \$window\.Width'
        $script:AppSrc | Should -Match 'Get-SlopChatWindowRect[\s\S]{0,240}?-PetHeight \$window\.Height'
    }
}
