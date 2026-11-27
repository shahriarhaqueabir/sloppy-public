# Headless contract for the separate transparent chat window.
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 6.0

$module = Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1'
if (Test-Path -LiteralPath $module) { . $module }
$appSourcePath = Join-Path $PSScriptRoot '../src/Slop.ps1'

Describe 'Slop transparent chat window contract' {
    BeforeAll {
        $script:AppSrc = Get-Content -Raw -LiteralPath $appSourcePath
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

    It 'places the extended window next to the pet and clamps near the taskbar' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $near = Get-SlopChatWindowRect -PetLeft 100 -PetTop 100 -WorkArea $wa
        $near.Left | Should -Be 150
        $near.Top | Should -Be 0
        $near.Width | Should -Be 760
        $near.Height | Should -Be 540
        $far = Get-SlopChatWindowRect -PetLeft 1700 -PetTop 900 -WorkArea $wa
        $far.Left | Should -Be 1160
        $far.Top | Should -Be 500
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
        $script:AppSrc | Should -Not -Match 'Mica|Acrylic|DwmSetWindowAttribute|SetWindowCompositionAttribute'
    }

    It 'uses accessible text colours in the chat window' {
        $xaml = Get-SlopChatWindowXaml
        $xaml | Should -Not -Match '8A8A96'
        $xaml | Should -Match '93A4BD'
        $xaml | Should -Not -Match 'FontSize="9"'
    }
}
