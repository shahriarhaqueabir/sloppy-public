#requires -Version 7.6
Describe 'Slop.OpenCodeCompat' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeCompat.ps1')
    }
    It 'declares a supported version floor and records the newest verified release' {
        $contract = Get-SlopOpenCodeCompatContract
        $contract.MinimumVersion | Should -Be '2.3.2'
        $contract.VerifiedVersion | Should -Be '2.4.2'
        Test-SlopVersionAtLeast -Version $contract.VerifiedVersion -Minimum $contract.MinimumVersion | Should -BeTrue
    }
    It 'declares every route the Tier 2 bridge actually calls' {
        $paths = (Get-SlopOpenCodeCompatContract).RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path }
        $paths | Should -Contain 'POST /api/session/{id}/model'
        $paths | Should -Contain 'POST /api/session/{id}/agent'
        $paths | Should -Contain 'DELETE /api/session/{id}'
        $paths | Should -Contain 'POST /api/session/{id}/permission/{permissionID}/reply'
        $paths | Should -Contain 'GET /api/event?types=...'
    }
    It 'fails closed below the supported minimum' {
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version='1.19.6'; routes=@() }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match 'version'
    }
    It 'fails closed on a malformed version' {
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version='unknown'; routes=@() }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match 'version'
    }
    It 'compares version parts numerically rather than lexically' {
        Test-SlopVersionAtLeast -Version '2.10.0' -Minimum '2.3.2' | Should -BeTrue
        Test-SlopVersionAtLeast -Version '2.3.2' -Minimum '2.10.0' | Should -BeFalse
        Test-SlopVersionAtLeast -Version 'v2.4.2' -Minimum '2.3.2' | Should -BeTrue
    }
    It 'accepts the verified release and newer versions without a pin update' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path })
        foreach ($version in @('2.3.2', '2.4.2', '2.5.0', '3.0.0', 'v2.4.2')) {
            $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$version; routes=$routes }
            $r.Ok | Should -BeTrue
        }
    }
    It 'fails closed when a required route is missing' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | Where-Object { $_.Path -ne '/api/session/{id}/model' } |
            ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.VerifiedVersion; routes=$routes }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match '/api/session/\{id\}/model'
    }
    It 'passes when a supported version exposes every required route' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.VerifiedVersion; routes=$routes }
        $r.Ok | Should -BeTrue
    }
}
