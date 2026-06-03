$script:CleanCliRoot = $PSScriptRoot
$script:CleanCliState = [ordered]@{
    Enabled = $false
    OriginalPrompt = $null
    OriginalContinuationPrompt = $null
    OriginalPromptText = $null
    OriginalExtraPromptLineCount = $null
    OriginalPSReadLineOptionsCaptured = $false
    OriginalKeyHandlers = @{}
    OriginalAliases = @{}
    IconAliasesEnabled = $false
    LastPromptMilliseconds = 0
    LastGitDurationMilliseconds = 0
    LastGit = $null
    LastSlowGit = $null
    LastGitProcessCount = 0
    LastDirectoryReadAheadPath = ''
    LastDirectoryReadAheadDurationMilliseconds = 0
    LastDirectoryReadAheadSkippedReason = ''
    LastDirectoryGitStatusCount = 0
    LastDirectoryGitStatusDurationMilliseconds = 0
    LastDirectoryGitStatusTimedOutCount = 0
    HostName = $null
    LoadStatus = 'not-started'
    LoadReason = ''
    StartedAt = [datetime]::Now
}
$script:CleanCliProfileState = [ordered]@{
    Identifier = $null
    ProfileName = $null
    Mapped = $false
    ProfilesPath = $null
    MasterSettings = [ordered]@{}
    ProfileSettings = [ordered]@{}
}
$script:CleanCliProfilePromptReader = $null
$script:CleanCliMachineIdentifierOverride = $null
$script:CleanCliGitCache = @{}
$script:CleanCliGitLastSuccessful = @{}
$script:CleanCliGitAsyncRefreshes = @{}
$script:CleanCliDirectoryMetadataCache = @{}
$script:CleanCliDirectoryReadAheadJobs = @{}
$script:CleanCliDirectoryReadAheadPending = @{}
$script:CleanCliDirectoryReadAheadLastRequest = @{}
$script:CleanCliDirectoryReadAheadMaxActive = 1
$script:CleanCliGitCommand = $null
$script:CleanCliGitAsyncCommand = $null
$script:CleanCliDirectoryReadAheadCommand = $null
$script:CleanCliCommandDurationProvider = $null
$script:CleanCliGitTimeoutMilliseconds = 1000
$script:CleanCliGitCacheMilliseconds = 750
$script:CleanCliDefaultOptions = [ordered]@{
    GitTimeoutMilliseconds = 1000
    GitCacheMilliseconds = 750
    GitSlowSuppressionTimeouts = 2
    GitUntrackedMode = 'normal'
    GitIgnoreSubmodules = 'none'
    GitStatusMode = 'full'
    GitDivergenceMode = 'none'
    DirectoryReadAheadMode = 'metadata'
    DirectoryReadAheadDepth = 1
    DirectoryMetadataCacheMilliseconds = 5000
    DirectoryReadAheadMaxDirectories = 64
    DirectoryReadAheadDebounceMilliseconds = 250
    DirectoryGitStatusMode = 'disabled'
    PathDisplayMode = 'auto'
    PromptLayout = 'single'
    IconMode = 'disabled'
    CommandDurationThresholdMilliseconds = 2000
    RightPrompt = $false
    PromptSeparator = 'auto'
    PathSymbol = 'auto'
    GitSymbol = 'auto'
    DirtySymbol = 'auto'
    AdminSymbol = 'auto'
    TimeSymbol = 'auto'
    AdminForeground = 'Yellow'
    AdminBackground = 'Black'
    PathForeground = 'White'
    PathBackground = 'Magenta'
    GitForeground = 'Black'
    GitBackground = 'Green'
    TimeForeground = 'Black'
    TimeBackground = 'Yellow'
    KeyBindingPreset = 'zsh'
    EnableInCodex = $true
    EnableInVSCode = $true
    EnableInWindowsTerminal = $true
    EnableInPlainConsole = $true
    AsciiMode = $false
    TransientPrompt = $false
}
$script:CleanCliOptions = [ordered]@{}
$script:CleanCliConfigPath = $null
$script:CleanCliSlowGitRepositories = @{}

. (Join-Path $script:CleanCliRoot 'Config.ps1')
. (Join-Path $script:CleanCliRoot 'Git.ps1')
. (Join-Path $script:CleanCliRoot 'DirectoryCache.ps1')
. (Join-Path $script:CleanCliRoot 'Prompt.ps1')
. (Join-Path $script:CleanCliRoot 'PSReadLine.ps1')
. (Join-Path $script:CleanCliRoot 'Icons.ps1')
. (Join-Path $script:CleanCliRoot 'Navigation.ps1')
. (Join-Path $script:CleanCliRoot 'Operations.ps1')

function Enable-CleanCli {
    [CmdletBinding()]
    param()

    if ($script:CleanCliState.Enabled) {
        return
    }

    $script:CleanCliState.OriginalPrompt = $function:global:prompt

    Initialize-CleanCliOptions | Out-Null
    $script:CleanCliState.HostName = Get-CleanCliHostName
    if (-not (Test-CleanCliHostEnabled -HostName $script:CleanCliState.HostName)) {
        $script:CleanCliState.LoadStatus = 'skipped'
        $script:CleanCliState.LoadReason = "$($script:CleanCliState.HostName) host disabled by CleanCli config."
        return
    }

    Invoke-CleanCliProfileSetupPrompt
    Set-CleanCliPSReadLine
    Set-CleanCliIconAliases
    Set-Item -Path Function:\global:prompt -Value {
        $module = Get-Module CleanCli
        if ($module) {
            return & $module { Invoke-CleanCliPrompt }
        }

        'PS> '
    }
    $script:CleanCliState.Enabled = $true
    $script:CleanCliState.LoadStatus = 'enabled'
    $script:CleanCliState.LoadReason = "$($script:CleanCliState.HostName) host enabled."
}

function Disable-CleanCli {
    [CmdletBinding()]
    param()

    if ($null -ne $script:CleanCliState.OriginalPrompt) {
        Set-Item -Path Function:\global:prompt -Value $script:CleanCliState.OriginalPrompt
    }

    Restore-CleanCliPSReadLine
    Restore-CleanCliIconAliases
    $script:CleanCliState.Enabled = $false
}

function Get-CleanCliStatus {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Enabled = [bool]$script:CleanCliState.Enabled
        ModuleRoot = $script:CleanCliRoot
        LastPromptMilliseconds = [math]::Round([double]$script:CleanCliState.LastPromptMilliseconds, 2)
        LastGitDurationMilliseconds = [math]::Round([double]$script:CleanCliState.LastGitDurationMilliseconds, 2)
        LastGit = $script:CleanCliState.LastGit
        LastSlowGit = $script:CleanCliState.LastSlowGit
        HostName = $script:CleanCliState.HostName
        LoadStatus = $script:CleanCliState.LoadStatus
        LoadReason = $script:CleanCliState.LoadReason
        GitCacheEntries = $script:CleanCliGitCache.Count
        GitTimeoutMilliseconds = $script:CleanCliGitTimeoutMilliseconds
        GitProcessCount = $script:CleanCliState.LastGitProcessCount
        DirectoryMetadataCacheEntries = $script:CleanCliDirectoryMetadataCache.Count
        DirectoryReadAheadPendingCount = $script:CleanCliDirectoryReadAheadPending.Count
        DirectoryReadAheadActiveCount = $script:CleanCliDirectoryReadAheadJobs.Count
        LastDirectoryReadAheadPath = $script:CleanCliState.LastDirectoryReadAheadPath
        LastDirectoryReadAheadDurationMilliseconds = [math]::Round([double]$script:CleanCliState.LastDirectoryReadAheadDurationMilliseconds, 2)
        LastDirectoryReadAheadSkippedReason = $script:CleanCliState.LastDirectoryReadAheadSkippedReason
        LastDirectoryGitStatusCount = $script:CleanCliState.LastDirectoryGitStatusCount
        LastDirectoryGitStatusDurationMilliseconds = [math]::Round([double]$script:CleanCliState.LastDirectoryGitStatusDurationMilliseconds, 2)
        LastDirectoryGitStatusTimedOutCount = $script:CleanCliState.LastDirectoryGitStatusTimedOutCount
        AsciiMode = $env:CLEANCLI_ASCII -eq '1'
        ProfileIdentifier = $script:CleanCliProfileState.Identifier
        ProfileName = $script:CleanCliProfileState.ProfileName
        ProfileMapped = [bool]$script:CleanCliProfileState.Mapped
        ProfilesPath = $script:CleanCliProfileState.ProfilesPath
        StartedAt = $script:CleanCliState.StartedAt
    }
}

function Measure-CleanCliStartup {
    [CmdletBinding()]
    param(
        [string]$PowerShellPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source,
        [ValidateRange(1, 50)]
        [int]$Iterations = 1
    )

    if (-not $PowerShellPath) {
        $PowerShellPath = (Get-Command powershell).Source
    }

    $modulePath = Join-Path $script:CleanCliRoot 'CleanCli.psd1'

    $samples = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $Iterations; $index++) {
        $noProfile = Measure-Command {
            & $PowerShellPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString() | Out-Null'
        }
        $cleanCliImport = Measure-Command {
            & $PowerShellPath -NoProfile -Command "Import-Module '$modulePath' -Force"
        }
        $cleanCliEnable = Measure-Command {
            & $PowerShellPath -NoProfile -Command "Import-Module '$modulePath' -Force; Enable-CleanCli; Get-CleanCliStatus | Out-Null"
        }
        $terminalIconsImport = Measure-Command {
            & $PowerShellPath -NoProfile -Command 'Import-Module Terminal-Icons -ErrorAction SilentlyContinue'
        }
        $cleanCliWithTerminalIcons = Measure-Command {
            & $PowerShellPath -NoProfile -Command "Import-Module Terminal-Icons -ErrorAction SilentlyContinue; Import-Module '$modulePath' -Force; Enable-CleanCli; Get-CleanCliStatus | Out-Null"
        }
        $profileLoad = Measure-Command {
            & $PowerShellPath -Command 'exit'
        }
        $oldInteractiveOnly = $env:CLEANCLI_INTERACTIVE_ONLY
        try {
            $env:CLEANCLI_INTERACTIVE_ONLY = '0'
            $forcedProfileLoad = Measure-Command {
                & $PowerShellPath -Command 'exit'
            }
        }
        finally {
            if ($null -eq $oldInteractiveOnly) {
                Remove-Item Env:\CLEANCLI_INTERACTIVE_ONLY -ErrorAction SilentlyContinue
            }
            else {
                $env:CLEANCLI_INTERACTIVE_ONLY = $oldInteractiveOnly
            }
        }

        $samples.Add([pscustomobject]@{
            NoProfileMilliseconds = [math]::Round($noProfile.TotalMilliseconds, 2)
            CleanCliImportMilliseconds = [math]::Round($cleanCliImport.TotalMilliseconds, 2)
            CleanCliEnableMilliseconds = [math]::Round($cleanCliEnable.TotalMilliseconds, 2)
            TerminalIconsImportMilliseconds = [math]::Round($terminalIconsImport.TotalMilliseconds, 2)
            CleanCliWithTerminalIconsMilliseconds = [math]::Round($cleanCliWithTerminalIcons.TotalMilliseconds, 2)
            ProfileLoadMilliseconds = [math]::Round($profileLoad.TotalMilliseconds, 2)
            ForcedProfileLoadMilliseconds = [math]::Round($forcedProfileLoad.TotalMilliseconds, 2)
        }) | Out-Null
    }

    function Add-CleanCliStartupStatistic {
        param(
            [System.Collections.IDictionary]$Target,
            [string]$Name
        )

        $values = @($samples | ForEach-Object { [double]$_.$Name })
        $measure = $values | Measure-Object -Minimum -Maximum -Average
        $Target["${Name}Minimum"] = [math]::Round([double]$measure.Minimum, 2)
        $Target["${Name}Average"] = [math]::Round([double]$measure.Average, 2)
        $Target["${Name}Maximum"] = [math]::Round([double]$measure.Maximum, 2)
    }

    $last = $samples[$samples.Count - 1]
    $result = [ordered]@{
        Iterations = $Iterations
        NoProfileMilliseconds = $last.NoProfileMilliseconds
        CleanCliImportMilliseconds = $last.CleanCliImportMilliseconds
        CleanCliEnableMilliseconds = $last.CleanCliEnableMilliseconds
        TerminalIconsImportMilliseconds = $last.TerminalIconsImportMilliseconds
        CleanCliWithTerminalIconsMilliseconds = $last.CleanCliWithTerminalIconsMilliseconds
        ProfileLoadMilliseconds = $last.ProfileLoadMilliseconds
        ForcedProfileLoadMilliseconds = $last.ForcedProfileLoadMilliseconds
    }
    foreach ($name in @(
        'NoProfileMilliseconds'
        'CleanCliImportMilliseconds'
        'CleanCliEnableMilliseconds'
        'TerminalIconsImportMilliseconds'
        'CleanCliWithTerminalIconsMilliseconds'
        'ProfileLoadMilliseconds'
        'ForcedProfileLoadMilliseconds'
    )) {
        Add-CleanCliStartupStatistic -Target $result -Name $name
    }

    [pscustomobject]$result
}

Export-ModuleMember -Function Enable-CleanCli, Disable-CleanCli, Get-CleanCliStatus, Measure-CleanCliStartup, Get-CleanCliOption, Set-CleanCliOption, Get-CleanCliChildItem, Get-CleanCliIconDiagnostics, Set-CleanCliLocation, Get-CleanCliLocationHistory, Open-CleanCliExplorer, Show-CleanCliGitLog, Install-CleanCli, Get-CleanCliProfile, New-CleanCliMachineProfile, Set-CleanCliMachineProfile
