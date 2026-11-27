# Adapter contract and request planning. Headless; no WPF and no network.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopIdentityColors -ErrorAction SilentlyContinue)) {
    throw 'Slop.Config.ps1 must be dot-sourced before Slop.Provider.ps1'
}
. (Join-Path $PSScriptRoot 'Slop.LocalModel.ps1')

function Get-SlopAdapterContract {
    return @{
        Version        = 1
        MarkerContract = @('__DONE__', '__CONNECTED__', '__WARN__', '__ERR__', '__TOK__', '__OC', '__THINK__')
        QueueType      = 'System.Collections.Concurrent.ConcurrentQueue[string]'
        EntryPoint     = 'Invoke-SlopAdapter'
    }
}

function Get-SlopAttachmentMediaType {
    param([Parameter(Mandatory)][string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.wav'  { return 'audio/wav' }
        '.mp3'  { return 'audio/mpeg' }
        '.m4a'  { return 'audio/mp4' }
        '.ogg'  { return 'audio/ogg' }
        '.flac' { return 'audio/flac' }
        '.png'  { return 'image/png' }
        '.jpg'  { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.webp' { return 'image/webp' }
        '.gif'  { return 'image/gif' }
        default { return $null }
    }
}

function Get-SlopAttachmentFormat {
    param([Parameter(Mandatory)][string]$MediaType)
    switch ($MediaType) {
        'audio/wav'   { return 'wav' }
        'audio/mpeg'  { return 'mp3' }
        'audio/mp4'   { return 'mp4' }
        'audio/ogg'   { return 'ogg' }
        'audio/flac'  { return 'flac' }
        default       { return $null }
    }
}

function New-SlopAttachmentFromFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 12000000
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "attachment file not found: $Path" }
    $mediaType = Get-SlopAttachmentMediaType -Path $Path
    if (-not $mediaType) { throw "unsupported attachment type: $([IO.Path]::GetExtension($Path))" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt $MaxBytes) { throw "attachment exceeds $MaxBytes bytes" }
    $kind = if ($mediaType.StartsWith('audio/')) { 'audio' } elseif ($mediaType.StartsWith('image/')) { 'image' } else { throw "unsupported attachment type: $mediaType" }
    return @{
        type = $kind
        path = $Path
        name = [IO.Path]::GetFileName($Path)
        mediaType = $mediaType
        dataBase64 = [Convert]::ToBase64String($bytes)
    }
}

function ConvertTo-SlopChatContentPart {
    param([Parameter(Mandatory)][hashtable]$Attachment)
    $type = [string]$Attachment.type
    $mediaType = [string]$Attachment.mediaType
    $data = [string]$Attachment.dataBase64
    if ([string]::IsNullOrWhiteSpace($data)) { throw 'attachment dataBase64 is required' }
    if ($data.Length -gt 16000000) { throw 'attachment exceeds maximum encoded size' }
    switch ($type) {
        'audio' {
            $fmt = Get-SlopAttachmentFormat -MediaType $mediaType
            if (-not $fmt) { throw "unsupported audio media type: $mediaType" }
            return @{ type = 'input_audio'; input_audio = @{ data = $data; format = $fmt } }
        }
        'image' {
            if ($mediaType -notmatch '^image/(png|jpeg|webp|gif)$') { throw "unsupported image media type: $mediaType" }
            return @{ type = 'image_url'; image_url = @{ url = "data:$mediaType;base64,$data" } }
        }
        default { throw "unsupported attachment type: $type" }
    }
}

function New-SlopChatRequestBody {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SystemPrompt,
        [Parameter(Mandatory)][AllowEmptyString()][string]$UserText,
        [object[]]$History = @(),
        [object[]]$Attachments = @(),
        [int]$MaxLength = 8000,
        [switch]$DisableThinking
    )
    if ($UserText.Length -gt $MaxLength) { throw "prompt exceeds $MaxLength characters" }
    $messages = [Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
        $messages.Add(@{ role = 'system'; content = $SystemPrompt })
    }
    foreach ($item in @($History | Select-Object -Last 24)) {
        $role = [string]$item.role
        $content = [string]$item.content
        if ($role -notin @('user','assistant')) { throw 'history role must be user or assistant' }
        if ($content.Length -gt $MaxLength) { throw "history message exceeds $MaxLength characters" }
        $messages.Add(@{ role = $role; content = $content })
    }

    $atts = @($Attachments | Where-Object { $null -ne $_ })
    if ($atts.Count -gt 0) {
        $parts = [Collections.Generic.List[object]]::new()
        $parts.Add(@{ type = 'text'; text = $UserText })
        foreach ($att in $atts) {
            $ht = if ($att -is [hashtable]) { $att } else { @{}; foreach ($p in $att.PSObject.Properties) { $ht[$p.Name] = $p.Value }; $ht }
            $parts.Add((ConvertTo-SlopChatContentPart -Attachment $ht))
        }
        $messages.Add(@{ role = 'user'; content = $parts.ToArray() })
    } else {
        $messages.Add(@{ role = 'user'; content = $UserText })
    }
    $result = @{
        model       = 'sloppy'
        messages    = $messages.ToArray()
        stream      = $true
        temperature = 0.8
        max_tokens  = 512
    }
    if ($DisableThinking) {
        $result.chat_template_kwargs = @{ enable_thinking = $false }
    }
    return $result | ConvertTo-Json -Depth 8 -Compress
}

# Part B supersedes the original SLOP_ADAPTER escape hatch: route selection now
# comes from config, and OpenCode is a first-class opt-in route.
function Get-SlopStreamPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$UserText,
        [string]$PersonaText = '',
        [object[]]$History = @(),
        [object[]]$Attachments = @(),
        [string]$ObservedProviderEndpointUrl = '',
        [hashtable]$OpenCodePermissionEvidence,
        [System.Diagnostics.Process]$LocalModelProcess,
        [Parameter(Mandatory)][string]$ScriptRootPath,
        [Parameter(Mandatory)][string]$RepoRootPath
    )
    . (Join-Path $PSScriptRoot 'Slop.Route.ps1')
    return Get-SlopRoutePlan -Config $Config -UserText $UserText -PersonaText $PersonaText `
        -History $History -Attachments $Attachments -ObservedProviderEndpointUrl $ObservedProviderEndpointUrl `
        -OpenCodePermissionEvidence $OpenCodePermissionEvidence `
        -LocalModelProcess $LocalModelProcess `
        -ScriptRootPath $ScriptRootPath -RepoRootPath $RepoRootPath
}
