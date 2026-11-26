# Provider-specific disclosure. Headless; no WPF, no network.
$ErrorActionPreference = 'Stop'

function New-SlopDisclosureText {
    param(
        [Parameter(Mandatory)][hashtable]$Route,
        [string]$TermsUrl = ''
    )
    $kind = [string]$Route.Kind
    $provider = [string]$Route.Provider
    $model = [string]$Route.Model

    if ($kind -eq 'local-bundled') {
        return @"
Route: Local · bundled · $model
Sloppy sends your message to its bundled llama-server on this PC over loopback HTTP. For the model request, nothing leaves this PC: it does not go to an internet provider, and inference does not require an internet connection.
"@
    }
    if ($kind -eq 'custom') {
        return @"
Route: Local · custom · $model
Sloppy sends your message to the OpenAI-compatible server you configured in Settings. No OpenCode account is involved. For the model request, nothing leaves this PC; the server you chose determines any further hops.
"@
    }
    if ($kind -eq 'opencode-local') {
        return @"
Route: Local · $provider · $model
Sloppy sends your message to OpenCode on this PC. OpenCode sends the prompt, selected agent instructions, and allowed context to the local provider $provider. The model request stays on this PC. Tools you enable can still reach other services; that is shown separately in Brain.
"@
    }
    $termsUri = $null
    $verified = [Uri]::TryCreate($TermsUrl, [UriKind]::Absolute, [ref]$termsUri) -and
        $termsUri.Scheme -eq 'https' -and [string]::IsNullOrEmpty($termsUri.UserInfo)
    $termsLine = if ($verified) { "Verified terms and privacy information: $TermsUrl" } else { 'No verified terms link is available for this provider/model yet. Treat retention and training terms as unknown.' }
    return @"
Route: Remote · $provider · $model
Sloppy draws the pea and holds the conversation. Your message goes first to OpenCode on this PC. OpenCode, an open-source (MIT) harness, then sends your message, the selected agent's instructions, and any files or tool results you allow to the selected model provider. The selected provider processes that request under its own terms. Sloppy cannot set the provider's retention or model-training policy.
$termsLine
Retention and training terms differ by provider and model and can change. We do not claim any model is permanently free.
"@
}

function Get-SlopDeletionCopy {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    switch ($Action) {
        'conversation' { return 'Clear conversation removes the Sloppy transcript only. The OpenCode session and its stored messages remain.' }
        'session'      { return 'Delete OpenCode session removes that session and its child sessions from OpenCode''s local store. It does not mean the provider deleted its copy of a prompt or transcript.' }
        'local-data'   { return 'Clear Sloppy local data removes config.json and persona.md from the data folder inside your Sloppy install. It does not delete OpenCode sessions or provider data.' }
    }
}
