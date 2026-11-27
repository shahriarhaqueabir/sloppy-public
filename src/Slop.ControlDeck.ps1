# Pure control deck catalog. No WPF.
$ErrorActionPreference = 'Stop'

function Get-SlopControlDeckSections {
    return @(
        @{ Name = 'Overview';       Key = 'overview' }
        @{ Name = 'Settings';       Key = 'settings' }
        @{ Name = 'Data';           Key = 'data' }
        @{ Name = 'Tools & Skills'; Key = 'tools' }
        @{ Name = 'Under the hood'; Key = 'underTheHood' }
        @{ Name = 'Exit';           Key = 'exit' }
    )
}

function Get-SlopControlDeckToggleIds {
    return @(
        'WorkspaceFilesToggle'
        'WebAccessToggle'
        'ShellCommandsToggle'
        'SkillsPluginsToggle'
        'SubagentsTasksToggle'
        'ExternalFoldersToggle'
    )
}
