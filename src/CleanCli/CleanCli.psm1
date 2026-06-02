$script:CleanCliRoot = $PSScriptRoot
$script:CleanCliState = [ordered]@{
    Enabled = $false
    OriginalPrompt = $null
    OriginalContinuationPrompt = $null
    OriginalPromptText = $null
    OriginalKeyHandlers = @{}
    LastPromptMilliseconds = 0
    LastGitDurationMilliseconds = 0
    LastGit = $null
    LastSlowGit = $null
    LastGitProcessCount = 0
    StartedAt = [datetime]::Now
}
$script:CleanCliGitCache = @{}
$script:CleanCliGitLastSuccessful = @{}
$script:CleanCliGitAsyncRefreshes = @{}
$script:CleanCliGitCommand = $null
$script:CleanCliGitAsyncCommand = $null
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
    AsciiMode = $false
    TransientPrompt = $false
}
$script:CleanCliOptions = [ordered]@{}
$script:CleanCliConfigPath = $null
$script:CleanCliSlowGitRepositories = @{}

. (Join-Path $script:CleanCliRoot 'Config.ps1')
. (Join-Path $script:CleanCliRoot 'Git.ps1')
. (Join-Path $script:CleanCliRoot 'Prompt.ps1')
. (Join-Path $script:CleanCliRoot 'PSReadLine.ps1')

function Enable-CleanCli {
    [CmdletBinding()]
    param()

    if ($script:CleanCliState.Enabled) {
        return
    }

    $script:CleanCliState.OriginalPrompt = $function:global:prompt

    if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
        $options = Get-PSReadLineOption
        $script:CleanCliState.OriginalContinuationPrompt = $options.ContinuationPrompt
        $script:CleanCliState.OriginalPromptText = $options.PromptText
    }

    Initialize-CleanCliOptions | Out-Null
    Set-CleanCliPSReadLine
    Set-Item -Path Function:\global:prompt -Value {
        $module = Get-Module CleanCli
        if ($module) {
            return & $module { Invoke-CleanCliPrompt }
        }

        'PS> '
    }
    $script:CleanCliState.Enabled = $true
}

function Disable-CleanCli {
    [CmdletBinding()]
    param()

    if ($null -ne $script:CleanCliState.OriginalPrompt) {
        Set-Item -Path Function:\global:prompt -Value $script:CleanCliState.OriginalPrompt
    }

    Restore-CleanCliPSReadLine
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
        GitCacheEntries = $script:CleanCliGitCache.Count
        GitTimeoutMilliseconds = $script:CleanCliGitTimeoutMilliseconds
        GitProcessCount = $script:CleanCliState.LastGitProcessCount
        AsciiMode = $env:CLEANCLI_ASCII -eq '1'
        StartedAt = $script:CleanCliState.StartedAt
    }
}

function Measure-CleanCliStartup {
    [CmdletBinding()]
    param(
        [string]$PowerShellPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    )

    if (-not $PowerShellPath) {
        $PowerShellPath = (Get-Command powershell).Source
    }

    $modulePath = Join-Path $script:CleanCliRoot 'CleanCli.psd1'
    $noProfile = Measure-Command {
        & $PowerShellPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString() | Out-Null'
    }
    $moduleImport = Measure-Command {
        & $PowerShellPath -NoProfile -Command "Import-Module '$modulePath' -Force; Enable-CleanCli; Get-CleanCliStatus | Out-Null"
    }
    $profileLoad = Measure-Command {
        & $PowerShellPath -Command 'exit'
    }

    [pscustomobject]@{
        NoProfileMilliseconds = [math]::Round($noProfile.TotalMilliseconds, 2)
        ModuleImportMilliseconds = [math]::Round($moduleImport.TotalMilliseconds, 2)
        ProfileLoadMilliseconds = [math]::Round($profileLoad.TotalMilliseconds, 2)
    }
}

Export-ModuleMember -Function Enable-CleanCli, Disable-CleanCli, Get-CleanCliStatus, Measure-CleanCliStartup, Get-CleanCliOption, Set-CleanCliOption
