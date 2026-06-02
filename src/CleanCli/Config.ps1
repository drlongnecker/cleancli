function Copy-CleanCliOptions {
    param([hashtable]$Options)

    $copy = [ordered]@{}
    foreach ($key in $Options.Keys) {
        $copy[$key] = $Options[$key]
    }

    $copy
}

function Find-CleanCliConfigFile {
    param([string]$StartPath = (Get-Location).ProviderPath)

    if ($env:CLEANCLI_CONFIG_PATH) {
        return [System.IO.Path]::GetFullPath($env:CLEANCLI_CONFIG_PATH)
    }

    $item = Get-Item -LiteralPath $StartPath -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }

    $directory = if ($item.PSIsContainer) { $item } else { $item.Directory }
    while ($null -ne $directory) {
        $configPath = Join-Path $directory.FullName 'CleanCli.config.psd1'
        if (Test-Path -LiteralPath $configPath) {
            return $configPath
        }

        $directory = $directory.Parent
    }

    $null
}

function Get-CleanCliUserConfigPath {
    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    if (-not $documentsPath) {
        $documentsPath = [Environment]::GetFolderPath('UserProfile')
    }

    Join-Path (Join-Path $documentsPath 'PowerShell') 'CleanCli.config.psd1'
}

function ConvertTo-CleanCliOptionValue {
    param(
        [string]$Name,
        [object]$Value
    )

    switch ($Name) {
        'GitTimeoutMilliseconds' { return [int]$Value }
        'GitCacheMilliseconds' { return [int]$Value }
        'GitSlowSuppressionTimeouts' { return [int]$Value }
        'GitUntrackedMode' {
            $mode = [string]$Value
            if ($mode -notin @('no', 'normal', 'all')) {
                throw "GitUntrackedMode must be one of: no, normal, all."
            }
            return $mode
        }
        'GitIgnoreSubmodules' {
            $mode = [string]$Value
            if ($mode -notin @('none', 'untracked', 'dirty', 'all')) {
                throw "GitIgnoreSubmodules must be one of: none, untracked, dirty, all."
            }
            return $mode
        }
        'GitStatusMode' {
            $mode = [string]$Value
            if ($mode -notin @('full', 'branch', 'async')) {
                throw "GitStatusMode must be one of: full, branch, async."
            }
            return $mode
        }
        'GitDivergenceMode' {
            $mode = [string]$Value
            if ($mode -notin @('none', 'local')) {
                throw "GitDivergenceMode must be one of: none, local."
            }
            return $mode
        }
        'AsciiMode' { return [bool]$Value }
        'TransientPrompt' { return [bool]$Value }
    }

    throw "Unknown CleanCli option '$Name'."
}

function Merge-CleanCliOptions {
    param(
        [hashtable]$BaseOptions,
        [hashtable]$Overrides
    )

    $merged = Copy-CleanCliOptions -Options $BaseOptions
    foreach ($key in $Overrides.Keys) {
        $merged[$key] = ConvertTo-CleanCliOptionValue -Name $key -Value $Overrides[$key]
    }

    $merged
}

function Initialize-CleanCliOptions {
    param([string]$StartPath = (Get-Location).ProviderPath)

    $options = Copy-CleanCliOptions -Options $script:CleanCliDefaultOptions
    $configPath = Find-CleanCliConfigFile -StartPath $StartPath
    if ($configPath -and (Test-Path -LiteralPath $configPath)) {
        $loaded = Import-PowerShellDataFile -LiteralPath $configPath
        $options = Merge-CleanCliOptions -BaseOptions $options -Overrides $loaded
    }
    if (-not $configPath) {
        $configPath = Get-CleanCliUserConfigPath
    }

    if ($env:CLEANCLI_ASCII -eq '1') {
        $options.AsciiMode = $true
    }
    if ($env:CLEANCLI_TRANSIENT -eq '1') {
        $options.TransientPrompt = $true
    }

    $script:CleanCliOptions = $options
    $script:CleanCliConfigPath = $configPath
    $script:CleanCliGitTimeoutMilliseconds = $options.GitTimeoutMilliseconds
    $script:CleanCliGitCacheMilliseconds = $options.GitCacheMilliseconds

    [pscustomobject]$script:CleanCliOptions
}

function Save-CleanCliConfigFile {
    param(
        [string]$Path = $script:CleanCliConfigPath,
        [hashtable]$Options = $script:CleanCliOptions
    )

    if (-not $Path) {
        $Path = Get-CleanCliUserConfigPath
    }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@{')
    foreach ($key in $script:CleanCliDefaultOptions.Keys) {
        $value = $Options[$key]
        if ($value -is [bool]) {
            $rendered = if ($value) { '$true' } else { '$false' }
        }
        elseif ($value -is [string]) {
            $rendered = "'$($value.Replace("'", "''"))'"
        }
        else {
            $rendered = [string]$value
        }
        $lines.Add("    $key = $rendered")
    }
    $lines.Add('}')

    Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
    $script:CleanCliConfigPath = $Path
}

function Get-CleanCliOption {
    [CmdletBinding()]
    param([string]$Name)

    if ($script:CleanCliOptions.Count -eq 0) {
        Initialize-CleanCliOptions | Out-Null
    }

    if ($Name) {
        if (-not $script:CleanCliOptions.Contains($Name)) {
            throw "Unknown CleanCli option '$Name'."
        }

        return $script:CleanCliOptions[$Name]
    }

    [pscustomobject]$script:CleanCliOptions
}

function Set-CleanCliOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($script:CleanCliOptions.Count -eq 0) {
        Initialize-CleanCliOptions | Out-Null
    }

    $script:CleanCliOptions[$Name] = ConvertTo-CleanCliOptionValue -Name $Name -Value $Value
    if ($Name -eq 'GitTimeoutMilliseconds') {
        $script:CleanCliGitTimeoutMilliseconds = $script:CleanCliOptions[$Name]
    }
    if ($Name -eq 'GitCacheMilliseconds') {
        $script:CleanCliGitCacheMilliseconds = $script:CleanCliOptions[$Name]
    }
    Save-CleanCliConfigFile

    [pscustomobject]$script:CleanCliOptions
}
