#requires -Version 7.6
Describe 'Slop pane movement' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.PaneMovement.ps1')
        . (Join-Path $PSScriptRoot '../src/Slop.ChatWindow.ps1')
    }

    It 'uses a large inset preset for Full mode, not the whole work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopFullPaneRect -WorkArea $wa
        $r.Left | Should -Be 112
        $r.Top | Should -Be 72
        $r.Width | Should -Be 1696
        $r.Height | Should -Be 896
        $r.Left | Should -BeGreaterThan $wa.X
        $r.Top | Should -BeGreaterThan $wa.Y
        ($r.Left + $r.Width) | Should -BeLessThan ($wa.X + $wa.Width)
        ($r.Top + $r.Height) | Should -BeLessThan ($wa.Y + $wa.Height)
    }

    It 'moves a pane by a drag delta and clamps it inside the work area' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $r = Get-SlopMovedPaneRect -Rect @{ Left = 112; Top = 72; Width = 760; Height = 540 } `
            -DeltaX 2000 -DeltaY -500 -WorkArea $wa
        $r.Left | Should -Be 1160
        $r.Top | Should -Be 0
        $r.Width | Should -Be 760
        $r.Height | Should -Be 540
    }

    It 'keeps the pet visible and interactive in Extended but hidden in Full' {
        $extended = Get-SlopPanePetState -ChatMode Extended -ChatOpen $true
        $extended.Visible | Should -BeTrue
        $extended.Interactive | Should -BeTrue
        $extended.Topmost | Should -BeTrue

        $full = Get-SlopPanePetState -ChatMode Full -ChatOpen $true
        $full.Visible | Should -BeFalse
        $full.Interactive | Should -BeFalse
        $full.Topmost | Should -BeFalse
    }

    It 'restores the stored pet rect unchanged when Full closes' {
        $stored = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $restored = Get-SlopRestoredPetRect -StoredRect $stored
        $restored.Left | Should -Be 412
        $restored.Top | Should -Be 390
        $restored.Width | Should -Be 484
        $restored.Height | Should -Be 330
    }

    It 'exposes a drag grip helper that preserves pane size' {
        $grip = Get-SlopChatDragGripRect -Width 760 -Height 540
        $grip.Left | Should -Be 0
        $grip.Top | Should -Be 0
        $grip.Width | Should -Be 760
        $grip.Height | Should -Be 32
    }

    It 'offsets the opening chat away from a pinned pet' {
        $wa = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
        $pet = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $r = Get-SlopPinnedAwareChatRect -PetRect $pet `
            -RequestedRect @{ Left = 380; Top = 360; Width = 760; Height = 540 } -WorkArea $wa
        $r.Left | Should -Be 912
        $r.Top | Should -Be 360
        $r.Width | Should -Be 760
        $r.Height | Should -Be 540
        ($r.Left + $r.Width) | Should -BeLessThan ($wa.X + $wa.Width)
    }

    It 'ignores tiny clamp corrections so a topmost pane does not oscillate' {
        Test-SlopPaneClampNeeded -Value 3 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeFalse
        Test-SlopPaneClampNeeded -Value -5 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeTrue
        Test-SlopPaneClampNeeded -Value 105 -Minimum 0 -Maximum 100 -Tolerance 4 | Should -BeTrue
    }

    It 'never moves or resizes the pet while Extended chat is open' {
        $pet = @{ Left = 412; Top = 390; Width = 484; Height = 330 }
        $r = Get-SlopPetRectDuringChat -PetRect $pet -ChatMode Extended
        $r.Left | Should -Be 412
        $r.Top | Should -Be 390
        $r.Width | Should -Be 484
        $r.Height | Should -Be 330
    }
}
