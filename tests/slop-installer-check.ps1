#requires -Version 7.6
Describe 'Slop installer contracts' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
    }

    It 'pins both large assets with a destination and SHA-256' {
        $manifest = Get-Content (Join-Path $root 'tools/slop-assets.json') -Raw | ConvertFrom-Json
        $manifest.version | Should -Be 1
        $manifest.release | Should -Be 'v0.3.0'
        @($manifest.assets).Count | Should -Be 2
        foreach ($a in $manifest.assets) {
            $a.sha256 | Should -Match '^[0-9A-F]{64}$'
            $a.destination | Should -Not -Match '^\.'
            $a.url | Should -Match '^https://github\.com/shahriarhaqueabir/Sloppy/releases/download/v0\.3\.0/'
        }
        @($manifest.assets.name) | Should -Be @('Qwen3.5-2B-Q4_K_M.gguf','ggml-small.bin')
    }

    It 'hashes the actual bundled asset sizes' {
        $manifest = Get-Content (Join-Path $root 'tools/slop-assets.json') -Raw | ConvertFrom-Json
        $qwen = $manifest.assets | Where-Object { $_.name -eq 'Qwen3.5-2B-Q4_K_M.gguf' }
        $qwen.bytes | Should -Be 1312164352
        $qwen.sha256 | Should -Be '4E936E9D3DEDC45FA4CADB4A271FA50F8D6F3DB3BE0EADDC01DC4D6D356AA327'
        $whisper = $manifest.assets | Where-Object { $_.name -eq 'ggml-small.bin' }
        $whisper.bytes | Should -Be 487601967
        $whisper.sha256 | Should -Be '1BE3A9B2063867B937E64E2EC7483364A79917E157FA98C5D94B5C1FFFEA987B'
    }

    It 'fetches assets headlessly with checksum verification' {
        $src = Get-Content (Join-Path $root 'tools/slop-fetch-assets.ps1') -Raw
        $src | Should -Match 'Invoke-WebRequest'
        $src | Should -Match 'Get-FileHash .* -Algorithm SHA256'
        $src | Should -Match 'SLOP_TEST_ASSET_FIXTURES'
        $src | Should -Match '\.part'
        $src | Should -Match 'exit 1'
    }

    It 'uses Inno Setup with a user-chosen folder and an unchecked desktop task' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match 'DefaultDirName=\{autopf\}\\Sloppy'
        $iss | Should -Match 'PrivilegesRequired=lowest'
        $iss | Should -Match 'Name: desktopicon;.*Flags: unchecked'
        $iss | Should -Match '\{autodesktop\}\\Sloppy'
        $iss | Should -Match '\{group\}\\Sloppy'
        $iss | Should -Match '/DIR=' # documented in the installer comment header
    }

    It 'launches headlessly and protects user data on uninstall' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match '\{sys\}\\wscript\.exe'
        $iss | Should -Match 'run\.vbs'
        $iss | Should -Match 'Name: "?\{app\}\\data"?; Flags: uninsneveruninstall'
        $iss | Should -Match 'CurStepChanged'
        $iss | Should -Match 'SW_HIDE'
        $iss | Should -Not -Match 'pwsh\.exe""' # no direct PowerShell shortcut
    }

    It 'boots PowerShell before the post-install helper' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $iss | Should -Match 'Ensure-SlopPowerShell'
        $iss | Should -Match 'Microsoft\.PowerShell'
        $iss | Should -Match 'slop-fetch-assets\.ps1'
        $iss | Should -Match 'Get-PreviousSlopInstallRoot'
        $iss | Should -Match '\.sloppy-install\.json'
        $iss | Should -Match 'Key := ExpandConstant'
        $iss | Should -Match "FileSearch\('pwsh\.exe'"
        $iss | Should -Not -Match 'FileOrCmdExists|ACS_Quote'
    }

    It 'bundles only runtime source directories that exist in the repo' {
        $iss = Get-Content (Join-Path $root 'installer/Sloppy.iss') -Raw
        $missing = @()
        foreach ($m in [regex]::Matches($iss, '(?m)^Source: "\.\.\\([^"*]+)\\\*"')) {
            $rel = $m.Groups[1].Value
            if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) { $missing += $rel }
        }
        @($missing).Count | Should -Be 0
    }

    It 'maps the documented one-liner parameters to Inno switches' {
        $src = Get-Content (Join-Path $root 'install.ps1') -Raw
        $src | Should -Match 'param\('
        $src | Should -Match '\[string\]\$InstallDir'
        $src | Should -Match '\[switch\]\$DesktopShortcut'
        $src | Should -Match '/DIR='
        $src | Should -Match '/TASKS=desktopicon'
        $src | Should -Match '/VERYSILENT'
        $src | Should -Match 'SloppySetup\.exe'
        $src | Should -Not -Match 'git clone'
    }

    It 'launches from the script folder with no console window' {
        $vbs = Get-Content (Join-Path $root 'run.vbs') -Raw
        $vbs | Should -Match 'WScript\.ScriptFullName'
        $vbs | Should -Match '-WindowStyle Hidden'
        $vbs | Should -Match ', 0, False'
        $cmd = Get-Content (Join-Path $root 'run.cmd') -Raw
        $cmd | Should -Match 'wscript "%~dp0run\.vbs"'
    }

    It 'builds and publishes the installer from a tag' {
        $wf = Get-Content (Join-Path $root '.github/workflows/release.yml') -Raw
        $wf | Should -Match 'on:'
        $wf | Should -Match 'tags:'
        $wf | Should -Match 'InnoSetup'
        $wf | Should -Match '--version 6\.5\.4'
        $wf | Should -Match 'ISCC\.exe'
        $wf | Should -Match 'slop-fetch-assets\.ps1'
        $wf | Should -Match 'SLOP_TEST_ASSET_FIXTURES'
        $wf | Should -Match 'gh release view'
        $wf | Should -Match 'gh release create'
        $wf | Should -Match 'gh release upload'
        $wf | Should -Match 'SHA256SUMS\.txt'
        $wf | Should -Match 'lfs: true'
    }
}
