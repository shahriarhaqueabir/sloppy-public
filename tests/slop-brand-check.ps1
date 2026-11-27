# tests/slop-brand-check.ps1
# Headless brand + voice audit contract. No WPF types, no network, no live UI.
#requires -Version 7.4
Import-Module Pester -MinimumVersion 6.0

Describe 'Sloppy brand and voice audit' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        $script:module = Join-Path $script:root 'src/Slop.BrandAudit.ps1'
        $script:moduleExists = Test-Path -LiteralPath $script:module
        if ($script:moduleExists) { . $script:module }

        $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("slop-brand-probe-" + [guid]::NewGuid().ToString('N'))
        $fixtureDir = Join-Path $script:tempRoot 'src'
        $null = New-Item -ItemType Directory -Path $fixtureDir -Force
$fixture = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
  <StackPanel>
    <Button x:Name="FixtureBtn" Background="#123456" Width="20" Height="20"
            Content="We're excited to help you today." />
  </StackPanel>
</Window>
'@
        Set-Content -LiteralPath (Join-Path $fixtureDir 'Fixture.ps1') -Value ("`$xaml = @'`n" + $fixture + "`n'@`n") -Encoding utf8

        $script:fixtureFindings = @()
        if ($script:moduleExists -and (Get-Command Get-SlopBrandFindings -ErrorAction SilentlyContinue)) {
            $script:fixtureFindings = @(Get-SlopBrandFindings -Root $script:tempRoot)
        }

        $script:baseFinding = [pscustomobject]@{
            Surface = 'Fixture'
            File = 'src/Fixture.ps1'
            Line = 3
            Rule = 'token.literal'
            Value = '#123456'
            Severity = 'baselined'
            Reason = 'test reason'
        }
    }

    AfterAll {
        if ($script:tempRoot -and (Test-Path -LiteralPath $script:tempRoot)) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force
        }
    }

    It 'provides a pure audit module' {
        $script:moduleExists | Should -BeTrue
    }

    It 'exports the audit functions' {
        foreach ($name in @(
            'Get-SlopBrandSurfaces', 'Get-SlopBrandFindings', 'Test-SlopBrandContrast',
            'Compare-SlopBrandBaseline', 'New-SlopBrandReport', 'Test-SlopBrandGate'
        )) {
            Test-Path "function:$name" | Should -BeTrue -Because "$name must be exported"
        }
    }

    It 'discovers all three XAML surfaces in real source' {
        $surfaces = @(Get-SlopBrandSurfaces -Root $script:root | Where-Object { $_.Kind -eq 'Xaml' })
        $surfaces.Count | Should -Be 3
        $names = @($surfaces | ForEach-Object { $_.File })
        $names | Should -Contain 'src/Slop.ps1'
        $names | Should -Contain 'src/Slop.ChatWindow.ps1'
        $names | Should -Contain 'src/Slop.Onboarding.ps1'
    }

    It 'discovers the code-created disclosure dialog' {
        $code = @(Get-SlopBrandSurfaces -Root $script:root | Where-Object { $_.Kind -eq 'Code' })
        @($code | Where-Object { $_.File -eq 'src/Slop.ps1' -and $_.Line -eq 1972 }).Count |
            Should -Be 1
    }

    It 'reports seeded violations with file and line' {
        $rules = @($script:fixtureFindings | ForEach-Object { $_.Rule })
        $rules | Should -Contain 'token.literal'
        $rules | Should -Contain 'copy.voice'
        $rules | Should -Contain 'hit-target.small'
        foreach ($f in $script:fixtureFindings) {
            $f.File | Should -Not -BeNullOrEmpty
            $f.Line | Should -BeGreaterThan 0
        }
    }

    It 'computes contrast deterministically' {
        Test-SlopBrandContrast -Foreground '#FFFFFF' -Background '#000000' |
            Should -BeGreaterThan 20.9
        Test-SlopBrandContrast -Foreground '#000000' -Background '#FFFFFF' |
            Should -BeGreaterThan 20.9
    }

    It 'fails the baseline compare on a new finding' {
        $result = Compare-SlopBrandBaseline -Findings @($script:baseFinding) -Baseline @()
        $result.Ok | Should -BeFalse
        @($result.New).Count | Should -Be 1
    }

    It 'accepts a finding baselined with a reason' {
        $result = Compare-SlopBrandBaseline -Findings @($script:baseFinding) -Baseline @($script:baseFinding)
        $result.Ok | Should -BeTrue
        @($result.New).Count | Should -Be 0
    }

    It 'fails the baseline compare on an empty reason' {
        $bad = [pscustomobject]@{
            Surface = 'Fixture'; File = 'src/Fixture.ps1'; Line = 3
            Rule = 'token.literal'; Value = '#123456'; Severity = 'baselined'; Reason = ''
        }
        $result = Compare-SlopBrandBaseline -Findings @($script:baseFinding) -Baseline @($bad)
        $result.Ok | Should -BeFalse
        @($result.MissingReason).Count | Should -Be 1
    }

    It 'reports stale baseline entries without failing the ratchet' {
        $stale = [pscustomobject]@{
            Surface = 'Old'; File = 'src/Old.ps1'; Line = 9
            Rule = 'copy.literal'; Value = 'gone'; Severity = 'baselined'; Reason = 'removed'
        }
        $result = Compare-SlopBrandBaseline -Findings @($script:baseFinding) -Baseline @($script:baseFinding, $stale)
        $result.Ok | Should -BeTrue
        @($result.Stale).Count | Should -Be 1
    }

    It 'generates a report with the required columns and every finding' {
        $report = New-SlopBrandReport -Findings @($script:baseFinding)
        $report | Should -Match 'surface \| file \| line \| rule \| value \| severity \| exception reason'
        $report | Should -Match 'src/Fixture\.ps1'
        $report | Should -Match 'token\.literal'
        $report | Should -Match '#123456'
    }

    It 'includes a source-backed voice profile in the report' {
        $report = New-SlopBrandReport -Findings @()
        $report | Should -Match 'Voice profile'
        $report | Should -Match 'Banned Moves'
        $report | Should -Match 'agent/BRAND\.md'
    }

    It 'fails the gate closed on a hard finding' {
        $hard = [pscustomobject]@{
            Surface = 'Fixture'; File = 'src/Fixture.ps1'; Line = 3
            Rule = 'contrast.fail'; Value = '1.10'; Severity = 'hard'; Reason = 'bad pair'
        }
        $result = Compare-SlopBrandBaseline -Findings @($hard) -Baseline @($hard)
        $result.Ok | Should -BeFalse
        @($result.Errors).Count | Should -BeGreaterThan 0
    }
}

Describe 'Sloppy design style roles' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'src/Slop.BrandAudit.ps1')
        $script:requiredRoles = @(
            'slop.button.primary', 'slop.button.secondary', 'slop.button.danger',
            'slop.input', 'slop.checkbox', 'slop.combo', 'slop.card', 'slop.header',
            'slop.status.idle', 'slop.status.thinking', 'slop.status.working',
            'slop.status.success', 'slop.status.error'
        )
    }

    It 'exposes every required component style role' {
        foreach ($name in $script:requiredRoles) {
            { Get-SlopStyleRole -Name $name } | Should -Not -Throw -Because "$name must exist"
        }
    }

    It 'throws on an unknown style role' {
        { Get-SlopStyleRole -Name 'slop.role.unknown' } | Should -Throw
    }

    It 'resolves role tokens to existing design tokens' {
        foreach ($name in $script:requiredRoles) {
            $role = Get-SlopStyleRole -Name $name
            $role.Token | Should -Not -BeNullOrEmpty
            $role.TextToken | Should -Not -BeNullOrEmpty
            { Get-SlopDesignToken -Name $role.Token } | Should -Not -Throw
            { Get-SlopDesignToken -Name $role.TextToken } | Should -Not -Throw
        }
    }
}
