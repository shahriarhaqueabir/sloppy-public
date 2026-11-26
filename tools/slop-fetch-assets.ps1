# Headless post-install asset fetcher. Never writes outside the chosen install root.
#requires -Version 7.6
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$ManifestPath
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallRoot)
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

function Get-SlopAssetHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-SlopAsset {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sha256)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Get-SlopAssetHash -Path $Path) -eq $Sha256.ToUpperInvariant())
}

foreach ($asset in $manifest.assets) {
    $dest = Join-Path $root $asset.destination
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    if (Test-SlopAsset -Path $dest -Sha256 $asset.sha256) {
        Write-Host "Sloppy asset ready: $($asset.name)"
        continue
    }

    $copied = $false
    $fixtures = $env:SLOP_TEST_ASSET_FIXTURES
    if (-not [string]::IsNullOrWhiteSpace($fixtures)) {
        $fixturePath = Join-Path $fixtures $asset.name
        if (Test-SlopAsset -Path $fixturePath -Sha256 $asset.sha256) {
            Copy-Item -LiteralPath $fixturePath -Destination $dest -Force
            $copied = $true
        }
    }
    if (-not $copied) {
        $part = "$dest.part"
        try {
            Write-Host "Downloading $($asset.name) from $($asset.url)"
            Invoke-WebRequest -Uri $asset.url -OutFile $part -UseBasicParsing -TimeoutSec 30
            if (-not (Test-SlopAsset -Path $part -Sha256 $asset.sha256)) {
                throw "checksum mismatch for $($asset.name); expected $($asset.sha256)"
            }
            Move-Item -LiteralPath $part -Destination $dest -Force
            $copied = $true
        }
        catch {
            Write-Warning "Could not fetch $($asset.name): $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        }
    }
    if (-not $copied) {
        [Console]::Error.WriteLine("Sloppy could not install $($asset.name) from $($asset.url); install incomplete. Re-run setup to retry.")
        exit 1
    }
}
Write-Host 'Sloppy assets verified.'
