# Headless guards for the four destinations and deletion scopes. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopDestinationMap {
    return @{
        Settings  = @('Startup behaviour','Data location','About and version','Advanced / developer')
        Customize = @('Name','Colour','Personality','Persona text')
        Brain     = @('Tier','Provider','Model','Agent','Capability profile','Effective model')
        Privacy   = @('Active data route','Provider terms','Deletion scopes','Deletion actions')
    }
}

function Get-SlopDestinationContract {
    param([Parameter(Mandatory)][ValidateSet('Settings','Customize','Brain','Privacy')][string]$Name)
    switch ($Name) {
        'Settings' {
            return @{
                Status   = 'SettingsStatusText'
                Editable = @('SettingsInstructionsBox','SettingsModelBox','SettingsBaseUrlBox','SettingsAgentIdBox','VoiceEnabledCheck','VoiceLanguageCombo','VoiceMaxSecondsBox')
                Actions  = @('SettingsSaveButton','AutostartButton','VoiceRepairButton','SettingsBack')
            }
        }
        'Customize' {
            return @{
                Status   = 'CustomizeStatusText'
                Editable = @('CustomizeNameBox','CustomizeColourCombo','CustomizePersonalityCombo','CustomizePersonaBox')
                Actions  = @('CustomizeSaveButton','CustomizeBack')
            }
        }
        'Brain' {
            return @{
                Status   = 'BrainStatusText'
                Editable = @('BrainTypeCombo','BrainProviderBox','BrainEndpointBox','BrainModelBox','BrainAgentIdBox','BrainProfileCombo')
                Actions  = @('BrainSaveButton','BrainBack')
            }
        }
        'Privacy' {
            return @{
                Status   = 'PrivacyStatusText'
                Editable = @()
                Actions  = @('DeleteConversationButton','DeleteSessionButton','DeleteLocalDataButton','PrivacyBack')
            }
        }
    }
}

function Test-SlopSurfaceSeparation {
    param([Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)][hashtable]$Payload)
    if ($Destination -eq 'Customize' -and $Payload.ContainsKey('permissions') -and @($Payload.permissions).Count -gt 0) {
        return @{ Ok=$false; Reason='Customize must never carry security permissions' }
    }
    return @{ Ok=$true; Reason=$null }
}

function Get-SlopDeletionScope {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    switch ($Action) {
        'conversation' { return @{ Scope='Sloppy transcript'; Copy=(Get-SlopDeletionCopy -Action 'conversation') } }
        'session'      { return @{ Scope='OpenCode session plus children'; Copy=(Get-SlopDeletionCopy -Action 'session') } }
        'local-data'   { return @{ Scope='{app}\data\config.json and persona.md'; Copy=(Get-SlopDeletionCopy -Action 'local-data') } }
    }
}
