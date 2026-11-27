# src/Slop.Face.ps1 — a soft field of alive pixels with switchable expression patterns.
# Geometry, colour and opacity come from the pure design-token layer.
$ErrorActionPreference = 'Stop'

$designModule = Join-Path $PSScriptRoot 'Slop.Design.ps1'
if (Test-Path -LiteralPath $designModule) { . $designModule }

$script:FaceDots = $null
$script:FaceLastPattern = $null
$script:FaceTransition = 1.0
$script:FaceLastTime = 0.0
$script:FaceFromNx = @()
$script:FaceFromNy = @()
$script:FaceToNx = @()
$script:FaceToNy = @()

function Initialize-SlopFaceDots {
    param(
        [int]$Count = ([int](Get-SlopDesignToken -Name 'face.count')),
        [int]$Seed = 1337
    )
    $rng = New-Object System.Random($Seed)
    $dots = @()
    # Light text roles double as particle colours: they stay legible over the
    # dark glass backplate and match the status palette used elsewhere.
    $palette = @(
        (Get-SlopDesignToken -Name 'text.focus'),
        (Get-SlopDesignToken -Name 'text.thinking'),
        (Get-SlopDesignToken -Name 'text.success'),
        (Get-SlopDesignToken -Name 'text.error'),
        (Get-SlopDesignToken -Name 'text.accent'),
        (Get-SlopDesignToken -Name 'text.primary')
    )
    $minSize = [double](Get-SlopDesignToken -Name 'face.size.min')
    $maxSize = [double](Get-SlopDesignToken -Name 'face.size.max')
    for ($i = 0; $i -lt $Count; $i++) {
        $dots += @{
            X = $rng.NextDouble()
            Y = $rng.NextDouble()
            Phase = $rng.NextDouble() * 6.283
            Freq = 0.6 + $rng.NextDouble() * 1.4
            Size = $minSize + $rng.NextDouble() * ($maxSize - $minSize)
            Color = $palette[$rng.Next($palette.Count)]
        }
    }
    $script:FaceDots = $dots
}

function New-SlopFaceLayer {
    param([int]$Seed = 1337)
    if (-not $script:FaceDots) { Initialize-SlopFaceDots -Seed $Seed }
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.IsHitTestVisible = $false
    foreach ($d in $script:FaceDots) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = $d.Size * 2
        $e.Height = $d.Size * 2
        $e.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($d.Color)
        $canvas.Children.Add($e) | Out-Null
    }
    return $canvas
}

function Update-SlopFaceLayer {
    param(
        [Parameter(Mandatory)]$Target,
        [double]$Time = 0.0,
        [double]$Speed = 1.0,
        [double]$Width = 100.0,
        [double]$Height = 100.0,
        [bool]$Frozen = $false,
        [ValidateSet('scattered','ring','cluster','line','spiral','wave','orbit','pulse','double-ring','grid','cross','star','heart','figure8','vortex','random-walk','breath','zigzag','flower','helix','diamond','triangle','crescent','burst')][string]$Pattern = 'scattered',
        [double]$Inset = 3.0
    )
    if (-not $script:FaceDots) { Initialize-SlopFaceDots }
    $phaseTime = if ($Frozen) { 0.0 } else { $Time }
    $w = [Math]::Max(10.0, $Width - 2 * $Inset)
    $h = [Math]::Max(10.0, $Height - 2 * $Inset)
    $count = [double]$script:FaceDots.Count
    $scatter = [double](Get-SlopDesignToken -Name 'face.scatter')

    # Transition tracking: blend between pattern states over ~0.7s.
    $patternChanged = ($script:FaceLastPattern -ne $Pattern)
    if ($patternChanged) {
        if ($script:FaceToNx.Count -eq $script:FaceDots.Count) {
            $script:FaceFromNx = @($script:FaceToNx)
            $script:FaceFromNy = @($script:FaceToNy)
        } else {
            $script:FaceFromNx = @(); $script:FaceFromNy = @()
            for ($i = 0; $i -lt $script:FaceDots.Count; $i++) {
                $script:FaceFromNx += $script:FaceDots[$i].X
                $script:FaceFromNy += $script:FaceDots[$i].Y
            }
        }
        $script:FaceTransition = 0.0
        $script:FaceLastPattern = $Pattern
    }
    if ($Frozen) {
        $script:FaceTransition = 1.0
        $tEase = 1.0
        $opacity = 1.0
    } else {
        $dt = if ($script:FaceLastTime -gt 0 -and $Time -gt $script:FaceLastTime) { [Math]::Min(0.25, $Time - $script:FaceLastTime) } else { 0.0 }
        $script:FaceLastTime = $Time
        if ($script:FaceTransition -lt 1.0) {
            $script:FaceTransition = [Math]::Min(1.0, $script:FaceTransition + $dt / 0.7)
        }
        $tEase = 1.0 - [Math]::Pow(1.0 - $script:FaceTransition, 3)
        $opacity = 1.0 - 0.75 * [Math]::Sin($script:FaceTransition * [Math]::PI)
    }

    $toNx = New-Object double[] $script:FaceDots.Count
    $toNy = New-Object double[] $script:FaceDots.Count
    for ($i = 0; $i -lt $script:FaceDots.Count; $i++) {
        $d = $script:FaceDots[$i]
        $el = $Target.Children[$i]
        $nx = $d.X
        $ny = $d.Y
        if ($Frozen) { $driftX = 0.0; $driftY = 0.0 }
        else {
            $driftX = 0.45 * [Math]::Sin($Time * $d.Freq * $Speed + $d.Phase)
            $driftY = 0.32 * [Math]::Cos($Time * $d.Freq * 0.7 * $Speed + $d.Phase)
        }
        switch ($Pattern) {
            'ring' { $a=(6.2831853*$i/$count)+$phaseTime*0.15*$Speed; $nx=0.5+$scatter*[Math]::Cos($a); $ny=0.5+$scatter*0.72*[Math]::Sin($a) }
            'spiral' { $a=$i*2.39996323+$phaseTime*0.12*$Speed; $r=$scatter*[Math]::Sqrt(($i+0.5)/$count); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*[Math]::Sin($a) }
            'cluster' { $nx=0.5+($d.X-0.5)*0.28+$driftX*0.3; $ny=0.5+($d.Y-0.5)*0.28+$driftY*0.3 }
            'line' { $nx=if($count -gt 1){0.16+0.68*($i/($count-1))}else{0.5}; $ny=0.46+$driftY*0.4 }
            'wave' { $nx=if($count -gt 1){0.10+0.80*($i/($count-1))}else{0.5}; $ny=0.5+0.22*[Math]::Sin($nx*6.283+$phaseTime*1.2*$Speed)+$driftY*0.3 }
            'orbit' { $ring=if($i%2-eq 0){0}else{1}; $r=if($ring-eq 0){0.22}else{$scatter}; $dir=if($ring-eq 0){1.0}else{-1.0}; $a=(6.2831853*[Math]::Floor($i/2)/([Math]::Ceiling($count/2.0)))+$phaseTime*0.2*$dir*$Speed; $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'pulse' { $a=6.2831853*$i/$count; $r=0.18+0.22*(0.5+0.5*[Math]::Sin($phaseTime*2.0*$Speed)); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'double-ring' { $ring=if($i%2-eq 0){0}else{1}; $r=if($ring-eq 0){0.20}else{0.38}; $a=(6.2831853*[Math]::Floor($i/2)/([Math]::Ceiling($count/2.0)))+$phaseTime*0.15*$Speed; $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'grid' { $cols=[Math]::Ceiling([Math]::Sqrt($count)); $row=[Math]::Floor($i/$cols); $col=$i%$cols; $nx=0.15+0.70*($col/[Math]::Max(1.0,$cols-1)); $ny=0.15+0.70*($row/[Math]::Max(1.0,$cols-1)) }
            'cross' { if($i%2-eq 0){ $nx=0.5; $ny=0.12+0.76*($i/[Math]::Max(1.0,$count-1)) } else { $nx=0.12+0.76*($i/[Math]::Max(1.0,$count-1)); $ny=0.5 } }
            'star' { $a=6.2831853*$i/$count; $r=if($i%2-eq 0){0.40}else{0.20}; $nx=0.5+$r*[Math]::Cos($a+$phaseTime*0.1*$Speed); $ny=0.5+$r*0.85*[Math]::Sin($a+$phaseTime*0.1*$Speed) }
            'heart' { $a=6.2831853*$i/$count; $hx=16*[Math]::Pow([Math]::Sin($a),3); $hy=13*[Math]::Cos($a)-5*[Math]::Cos(2*$a)-2*[Math]::Cos(3*$a)-[Math]::Cos(4*$a); $nx=0.5+$hx/40.0; $ny=0.5-$hy/40.0 }
            'figure8' { $a=6.2831853*$i/$count+$phaseTime*0.15*$Speed; $nx=0.5+0.36*[Math]::Sin($a); $ny=0.5+0.18*[Math]::Sin(2*$a) }
            'vortex' { $a=6.2831853*$i/$count+$phaseTime*0.4*$Speed; $r=0.12+0.30*($i/$count); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'random-walk' { $a=($i*137.508)%360; $r=0.15+0.25*(($i*7919)%100/100.0); $nx=0.5+$r*[Math]::Cos($a*0.01745+$phaseTime*0.3*$Speed); $ny=0.5+$r*0.85*[Math]::Sin($a*0.01745+$phaseTime*0.3*$Speed) }
            'breath' { $a=6.2831853*$i/$count; $r=0.28+0.12*(0.5+0.5*[Math]::Sin($phaseTime*1.2*$Speed)); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'zigzag' { if($count -gt 1){ $nx=0.10+0.80*($i/($count-1)); $ny=0.30+0.40*($i%2) } else { $nx=0.5;$ny=0.5 }; $ny += $driftY*0.3 }
            'flower' { $a=6.2831853*$i/$count; $r=0.32*(0.6+0.4*[Math]::Cos(6*$a+$phaseTime*0.5*$Speed)); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            'helix' { $a=6.2831853*$i/$count+$phaseTime*0.2*$Speed; $r=0.30; $nx=0.5+$r*[Math]::Cos($a); $ny=0.15+0.70*($i/[Math]::Max(1.0,$count-1)) }
            'diamond' { $t=($i/$count); $side=[Math]::Floor($t*4); $st=($t*4)-$side; switch($side){ 0{$nx=0.5+0.35*$st;$ny=0.15+0.35*$st} 1{$nx=0.85-0.35*$st;$ny=0.5+0.35*$st} 2{$nx=0.5-0.35*$st;$ny=0.85-0.35*$st} default{$nx=0.15+0.35*$st;$ny=0.5-0.35*$st} } }
            'triangle' { $t=($i/$count); $side=[Math]::Floor($t*3); $st=($t*3)-$side; switch($side){ 0{$nx=0.5;$ny=0.15+0.60*$st;$nx=0.5-0.30*$st} 1{$nx=0.20+0.60*$st;$ny=0.75} default{$nx=0.80-0.30*$st;$ny=0.75-0.60*$st} } }
            'crescent' { $a=6.2831853*$i/$count; $r=0.35; $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a); if($nx -gt 0.55){ $nx=0.55-($nx-0.55)*0.6 } }
            'burst' { $a=6.2831853*$i/$count+$phaseTime*0.05*$Speed; $r=0.10+0.34*(($i%3)/2.0); $nx=0.5+$r*[Math]::Cos($a); $ny=0.5+$r*0.85*[Math]::Sin($a) }
            default { $nx=$d.X+$driftX; $ny=$d.Y+$driftY }
        }
        $nx = [Math]::Min(1.0, [Math]::Max(0.0, $nx))
        $ny = [Math]::Min(1.0, [Math]::Max(0.0, $ny))
        $toNx[$i] = $nx; $toNy[$i] = $ny
    }
    $script:FaceToNx = $toNx; $script:FaceToNy = $toNy

    for ($i = 0; $i -lt $script:FaceDots.Count; $i++) {
        $el = $Target.Children[$i]
        $nx = $toNx[$i]; $ny = $toNy[$i]
        if ($script:FaceTransition -lt 1.0 -and $script:FaceFromNx.Count -eq $script:FaceDots.Count) {
            $nx = $script:FaceFromNx[$i] + ($nx - $script:FaceFromNx[$i]) * $tEase
            $ny = $script:FaceFromNy[$i] + ($ny - $script:FaceFromNy[$i]) * $tEase
        }
        $px = $Inset + $nx * $w
        $py = $Inset + $ny * $h
        [System.Windows.Controls.Canvas]::SetLeft($el, $px - $el.Width / 2)
        [System.Windows.Controls.Canvas]::SetTop($el, $py - $el.Height / 2)

        # Soft radial falloff: the field is brightest at the centre and fades
        # toward the rim. Position is untouched, so all placement contracts
        # stay valid, and a frozen field keeps a byte-identical opacity map.
        $dx = $nx - 0.5
        $dy = $ny - 0.5
        $distance = [Math]::Sqrt($dx * $dx + $dy * $dy) / 0.5
        if ($distance -gt 1.0) { $distance = 1.0 }
        $dotOpacity = [Math]::Max(0.05, $opacity * (1.0 - 0.55 * $distance))
        if ([Math]::Abs($el.Opacity - $dotOpacity) -gt 0.002) { $el.Opacity = $dotOpacity }
    }
}
