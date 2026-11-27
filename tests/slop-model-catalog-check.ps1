#requires -Version 7.6
Describe 'Slop.ModelCatalog' {
    BeforeAll {
        $script:Src = Join-Path $PSScriptRoot '../src'
        . (Join-Path $script:Src 'Slop.Config.ps1')
        . (Join-Path $script:Src 'Slop.ModelCatalog.ps1')

        $fixtureData = @{
            data = @(
                @{ id = 'big-pickle'; name = 'Big Pickle'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'opencode'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'z-free'; name = 'Z Free'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'a-free'; name = 'A Free'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'dup'; name = 'Wrong'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'dup'; name = 'Right'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'opencode'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'paid'; name = 'Paid'; type = 'chat'; status = 'active'; enabled = $true; providerID = 'other'; cost = @(@{ input = '1'; output = '2' }) }
                @{ id = 'off'; name = 'Off'; type = 'chat'; status = 'active'; enabled = $false; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'idle'; name = 'Idle'; type = 'chat'; status = 'inactive'; enabled = $true; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
                @{ id = 'tool'; name = 'Tool'; type = 'tool'; status = 'active'; enabled = $true; providerID = 'other'; cost = @(@{ input = '0'; output = '0' }) }
            )
        }
        $script:Fixture = ($fixtureData | ConvertTo-Json -Depth 8) | ConvertFrom-Json
    }

    It 'keeps only active, enabled, zero-cost chat models' {
        $models = @(Get-SlopFreeChatModels -CatalogData $script:Fixture)
        $models.Count | Should -Be 4
        $models.Id | Should -Be @('big-pickle', 'a-free', 'dup', 'z-free')
    }

    It 'deduplicates by id and prefers the opencode provider entry' {
        $models = @(Get-SlopFreeChatModels -CatalogData $script:Fixture)
        @($models | Where-Object { $_.Id -eq 'dup' }).Count | Should -Be 1
        ($models | Where-Object { $_.Id -eq 'dup' }).Name | Should -Be 'Right'
    }

    It 'pins big-pickle first and sorts the remaining models by name' {
        $models = @(Get-SlopFreeChatModels -CatalogData $script:Fixture)
        $models[0].Id | Should -Be 'big-pickle'
        $models[1].Name | Should -Be 'A Free'
        $models[2].Name | Should -Be 'Right'
        $models[3].Name | Should -Be 'Z Free'
    }

    It 'exposes only Id and Name from the filter' {
        $models = @(Get-SlopFreeChatModels -CatalogData $script:Fixture)
        foreach ($model in $models) {
            @($model.Keys | Sort-Object) | Should -Be @('Id', 'Name')
        }
    }

    It 'accepts a bare decoded data array' {
        $models = @(Get-SlopFreeChatModels -CatalogData @($script:Fixture.data))
        $models.Count | Should -Be 4
        $models[0].Id | Should -Be 'big-pickle'
    }

    It 'refuses a non-loopbase URL before making a request' {
        $result = Get-SlopModelCatalogResult -BaseUrl 'http://example.test'
        $result.Ok | Should -BeFalse
        @($result.Models).Count | Should -Be 0
        $result.Error | Should -Be 'OpenCode service URL must be loopback.'
    }

    It 'renders short status copy for failure, empty and populated results' {
        Get-SlopModelCatalogStatusText -Result @{ Ok = $false; Models = @(); Error = 'Offline.' } | Should -Be 'Offline.'
        Get-SlopModelCatalogStatusText -Result @{ Ok = $true; Models = @() } | Should -Be 'No free chat models returned.'
        Get-SlopModelCatalogStatusText -Result @{ Ok = $true; Models = @(@{ Id = 'a'; Name = 'A' }) } | Should -Be '1 free chat models available.'
    }

    It 'keeps the catalog module free of machine paths and service identifiers' {
        $src = Get-Content (Join-Path $script:Src 'Slop.ModelCatalog.ps1') -Raw
        $src | Should -Not -Match 'C:\\[A-Za-z0-9._-]+\\[A-Za-z0-9._-]+'
        $src | Should -Not -Match 'x-[a-z]+-[a-z-]+'
    }
}
