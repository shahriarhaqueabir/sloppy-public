#requires -Version 7.6
Describe 'Slop.OpenCodeCompat' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.OpenCodeCompat.ps1')
    }
    It 'pins the supported OpenCode version' {
        (Get-SlopOpenCodeCompatContract).PinnedVersion | Should -Be '2.4.2'
    }
    It 'declares every route the Tier 2 bridge actually calls' {
        $paths = (Get-SlopOpenCodeCompatContract).RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path }
        $paths | Should -Contain 'POST /api/session/{id}/model'
        $paths | Should -Contain 'POST /api/session/{id}/agent'
        $paths | Should -Contain 'DELETE /api/session/{id}'
        $paths | Should -Contain 'POST /api/session/{id}/permission/{permissionID}/reply'
        $paths | Should -Contain 'GET /api/event?types=...'
    }
    It 'fails closed on a version mismatch' {
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version='9.9.9'; routes=@() }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match 'version'
    }
    It 'fails closed when a required route is missing' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | Where-Object { $_.Path -ne '/api/session/{id}/model' } |
            ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.PinnedVersion; routes=$routes }
        $r.Ok | Should -BeFalse
        $r.Reasons -join ' ' | Should -Match '/api/session/\{id\}/model'
    }
    It 'passes when the pinned version exposes every required route' {
        $contract = Get-SlopOpenCodeCompatContract
        $routes = @($contract.RequiredRoutes | ForEach-Object { $_.Method + ' ' + $_.Path })
        $r = Test-SlopOpenCodeCompatContract -Observed @{ version=$contract.PinnedVersion; routes=$routes }
        $r.Ok | Should -BeTrue
    }
}
