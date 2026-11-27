#requires -Version 7.6
Describe 'Slop confirmed shutdown' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Shutdown.ps1')
        $script:ShellSrc = Get-Content (Join-Path $PSScriptRoot '../src/Slop.ps1') -Raw
    }

    It 'normalizes the phrase with optional comma, case, and punctuation' {
        foreach ($phrase in @('Sloppy, shutdown','sloppy shutdown','SLOPPY SHUTDOWN.',' sloppy; shutdown! ')) {
            (Test-SlopShutdownPhrase -Text $phrase) | Should -BeTrue
        }
        Test-SlopShutdownPhrase -Text 'Sloppy, shut down' | Should -BeFalse
    }

    It 'asks once and accepts yes, y, or confirm' {
        $state = New-SlopShutdownConfirmation
        $first = Resolve-SlopShutdownInput -State $state -Text 'Sloppy, shutdown'
        $first.ConfirmationRequired | Should -BeTrue
        foreach ($answer in @('yes','Y','confirm')) {
            $r = Resolve-SlopShutdownInput -State $first.State -Text $answer
            $r.ShouldShutdown | Should -BeTrue
        }
    }

    It 'cancels on any other response and resumes normal handling' {
        $first = Resolve-SlopShutdownInput -State (New-SlopShutdownConfirmation) -Text 'Sloppy, shutdown'
        $r = Resolve-SlopShutdownInput -State $first.State -Text 'no'
        $r.ShouldShutdown | Should -BeFalse
        $r.Cancelled | Should -BeTrue
        $r.TextForNormalHandling | Should -Be 'no'
    }

    It 'shows the exact confirmation prompt' {
        Get-SlopShutdownPrompt | Should -Be 'Are you sure? Say or type yes.'
    }

    It 'stops only the verified Sloppy-owned local brain during teardown' {
        $steps = @(Get-SlopShutdownTeardownSteps)
        $steps | Should -Be @('StopTimers','CancelStream','RejectPendingApprovals','DeleteOpenCodeSession','CloseChat','StopOwnedLocalModel','ShutdownApplication')
        $steps | Should -Not -Contain 'KillProcess'
        $script:ShellSrc | Should -Match 'Application\]::Current\.Shutdown\(\)'
        $script:ShellSrc | Should -Not -Match 'Stop-Process'

        $closed = [regex]::Match($script:ShellSrc, '(?s)\$window\.Add_Closed\(\{(?<body>.*?)\n\}\)')
        $closed.Success | Should -BeTrue
        $closedBody = $closed.Groups['body'].Value
        $closedBody | Should -Match 'Test-SlopOwnedModelProcess -Paths \$shutdownPaths -Process \$script:LocalModelProcess'
        $closedBody | Should -Match 'Stop-SlopLocalModel -Process \$script:LocalModelProcess'
    }
}
