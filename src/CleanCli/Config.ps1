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
    if ($script:CleanCliUserConfigPathOverride) {
        return $script:CleanCliUserConfigPathOverride
    }

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
        'DirectoryReadAheadMode' {
            $mode = [string]$Value
            if ($mode -notin @('disabled', 'metadata')) {
                throw "DirectoryReadAheadMode must be one of: disabled, metadata."
            }
            return $mode
        }
        'DirectoryGitStatusMode' {
            $mode = [string]$Value
            if ($mode -notin @('disabled', 'async')) {
                throw "DirectoryGitStatusMode must be one of: disabled, async."
            }
            return $mode
        }
        { $_ -in @('DirectoryReadAheadDepth', 'DirectoryMetadataCacheMilliseconds', 'DirectoryReadAheadMaxDirectories', 'DirectoryReadAheadDebounceMilliseconds') } {
            return [int]$Value
        }
        'DirectoryAlwaysShowGitBranches' { return [bool]$Value }
        'PathDisplayMode' {
            $mode = [string]$Value
            if ($mode -notin @('full', 'compact', 'auto')) {
                throw "PathDisplayMode must be one of: full, compact, auto."
            }
            return $mode
        }
        'PromptLayout' {
            $mode = [string]$Value
            if ($mode -notin @('single', 'two-line', 'auto')) {
                throw "PromptLayout must be one of: single, two-line, auto."
            }
            return $mode
        }
        'IconMode' {
            $mode = [string]$Value
            if ($mode -notin @('disabled', 'native', 'terminal-icons', 'ascii')) {
                throw "IconMode must be one of: disabled, native, terminal-icons, ascii."
            }
            return $mode
        }
        'CommandDurationThresholdMilliseconds' { return [int]$Value }
        'RightPrompt' { return [bool]$Value }
        { $_ -in @('PromptSeparator', 'PathSymbol', 'GitSymbol', 'DirtySymbol', 'AdminSymbol', 'TimeSymbol') } {
            return [string]$Value
        }
        { $_ -in @('AdminForeground', 'AdminBackground', 'PathForeground', 'PathBackground', 'GitForeground', 'GitBackground', 'TimeForeground', 'TimeBackground') } {
            $color = [string]$Value
            if ($color -notin @('Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White', 'DarkGray', 'Default')) {
                throw "$Name must be one of: Black, Red, Green, Yellow, Blue, Magenta, Cyan, White, DarkGray, Default."
            }
            return $color
        }
        'KeyBindingPreset' {
            $preset = [string]$Value
            if ($preset -notin @('zsh', 'powershell', 'minimal')) {
                throw "KeyBindingPreset must be one of: zsh, powershell, minimal."
            }
            return $preset
        }
        { $_ -in @('EnableInCodex', 'EnableInVSCode', 'EnableInWindowsTerminal', 'EnableInPlainConsole') } {
            return [bool]$Value
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

function Get-CleanCliProfilesPath {
    if ($env:CLEANCLI_PROFILES_PATH) {
        return [System.IO.Path]::GetFullPath($env:CLEANCLI_PROFILES_PATH)
    }

    $documentsPath = [Environment]::GetFolderPath('MyDocuments')
    if (-not $documentsPath) {
        $documentsPath = [Environment]::GetFolderPath('UserProfile')
    }

    Join-Path (Join-Path $documentsPath 'PowerShell') 'CleanCli.profiles.psd1'
}

function ConvertTo-CleanCliOrderedHashtable {
    param([object]$Value)

    $copy = [ordered]@{}
    if ($Value -isnot [System.Collections.IDictionary]) {
        return $copy
    }

    foreach ($key in $Value.Keys) {
        $copy[$key] = $Value[$key]
    }

    $copy
}

function Get-CleanCliDictionaryKey {
    param(
        [System.Collections.IDictionary]$Dictionary,
        [string]$Key
    )

    $profileKey = ConvertTo-CleanCliProfileKey -Value $Key
    foreach ($existingKey in $Dictionary.Keys) {
        if ((ConvertTo-CleanCliProfileKey -Value $existingKey) -eq $profileKey) {
            return $existingKey
        }
    }

    $null
}

function Read-CleanCliProfilesFile {
    param([string]$Path = (Get-CleanCliProfilesPath))

    $empty = [ordered]@{
        Master = [ordered]@{}
        Identifiers = [ordered]@{}
        Profiles = [ordered]@{}
    }

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$empty
    }

    $loaded = Import-PowerShellDataFile -LiteralPath $Path
    if ($loaded.Contains('Master')) {
        $empty.Master = ConvertTo-CleanCliOrderedHashtable -Value $loaded.Master
    }
    if ($loaded.Contains('Identifiers')) {
        $empty.Identifiers = ConvertTo-CleanCliOrderedHashtable -Value $loaded.Identifiers
    }
    if ($loaded.Contains('Profiles')) {
        $empty.Profiles = ConvertTo-CleanCliOrderedHashtable -Value $loaded.Profiles
    }

    [pscustomobject]$empty
}

function Format-CleanCliDataValue {
    param([object]$Value)

    if ($Value -is [bool]) {
        if ($Value) { return '$true' }
        return '$false'
    }

    if ($Value -is [string]) {
        return "'$($Value.Replace("'", "''"))'"
    }

    [string]$Value
}

function Save-CleanCliProfilesFile {
    param(
        [string]$Path = (Get-CleanCliProfilesPath),
        [object]$Data
    )

    if (-not $Data) {
        $Data = Read-CleanCliProfilesFile -Path $Path
    }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $master = ConvertTo-CleanCliOrderedHashtable -Value $Data.Master
    $identifiers = ConvertTo-CleanCliOrderedHashtable -Value $Data.Identifiers
    $profiles = ConvertTo-CleanCliOrderedHashtable -Value $Data.Profiles
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add('@{')
    $lines.Add('    Master = @{')
    foreach ($key in $master.Keys) {
        $value = ConvertTo-CleanCliOptionValue -Name $key -Value $master[$key]
        $lines.Add("        $(Format-CleanCliDataValue -Value ([string]$key)) = $(Format-CleanCliDataValue -Value $value)")
    }
    $lines.Add('    }')
    $lines.Add('    Identifiers = @{')
    foreach ($key in $identifiers.Keys) {
        $lines.Add("        $(Format-CleanCliDataValue -Value ([string]$key)) = $(Format-CleanCliDataValue -Value ([string]$identifiers[$key]))")
    }
    $lines.Add('    }')
    $lines.Add('    Profiles = @{')
    foreach ($profileName in $profiles.Keys) {
        $profileSettings = ConvertTo-CleanCliOrderedHashtable -Value $profiles[$profileName]
        $lines.Add("        $(Format-CleanCliDataValue -Value ([string]$profileName)) = @{")
        foreach ($key in $profileSettings.Keys) {
            $value = ConvertTo-CleanCliOptionValue -Name $key -Value $profileSettings[$key]
            $lines.Add("            $(Format-CleanCliDataValue -Value ([string]$key)) = $(Format-CleanCliDataValue -Value $value)")
        }
        $lines.Add('        }')
    }
    $lines.Add('    }')
    $lines.Add('}')

    Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Resolve-CleanCliProfileState {
    $identifier = Get-CleanCliMachineIdentifier
    $identifierKey = ConvertTo-CleanCliProfileKey -Value $identifier
    $profilesPath = Get-CleanCliProfilesPath
    $data = Read-CleanCliProfilesFile -Path $profilesPath
    $profileName = $null

    foreach ($configuredIdentifier in $data.Identifiers.Keys) {
        if ((ConvertTo-CleanCliProfileKey -Value $configuredIdentifier) -eq $identifierKey) {
            $profileName = $data.Identifiers[$configuredIdentifier]
            break
        }
    }

    $profileSettings = [ordered]@{}
    $mapped = $false
    $profileKey = Get-CleanCliDictionaryKey -Dictionary $data.Profiles -Key $profileName
    if ($profileKey) {
        $profileName = $profileKey
        $profileSettings = ConvertTo-CleanCliOrderedHashtable -Value $data.Profiles[$profileKey]
        $mapped = $true
    }

    $script:CleanCliProfileState.Identifier = $identifier
    $script:CleanCliProfileState.ProfileName = $profileName
    $script:CleanCliProfileState.Mapped = $mapped
    $script:CleanCliProfileState.ProfilesPath = $profilesPath
    $script:CleanCliProfileState.MasterSettings = ConvertTo-CleanCliOrderedHashtable -Value $data.Master
    $script:CleanCliProfileState.ProfileSettings = $profileSettings

    [pscustomobject]$script:CleanCliProfileState
}

function Read-CleanCliProfilePrompt {
    param([string]$Prompt)

    if ($script:CleanCliProfilePromptReader) { return & $script:CleanCliProfilePromptReader $Prompt }
    Read-Host -Prompt $Prompt
}

function Invoke-CleanCliProfileSetupPrompt {
    param([bool]$InteractiveOverride = (Test-CleanCliInteractiveConsole))

    if ($env:CLEANCLI_PROFILES_PROMPT -eq '0') { return }
    if (-not $InteractiveOverride) { return }
    if (-not $script:CleanCliProfileState.Identifier) { Resolve-CleanCliProfileState | Out-Null }
    if ($script:CleanCliProfileState.Mapped) { return }

    $answer = Read-CleanCliProfilePrompt -Prompt "CleanCli does not have a profile for $($script:CleanCliProfileState.Identifier).`nSet up this machine now? (y/n)"
    if ($answer -notmatch '^(y|yes)$') { return }

    $profileName = [string](Read-CleanCliProfilePrompt -Prompt "Profile name for $($script:CleanCliProfileState.Identifier)")
    $profileName = $profileName.Trim()
    if (-not $profileName) { return }

    New-CleanCliMachineProfile -ProfileName $profileName | Out-Null
}

function Initialize-CleanCliOptions {
    param([string]$StartPath = (Get-Location).ProviderPath)

    $options = Copy-CleanCliOptions -Options $script:CleanCliDefaultOptions
    $profileState = Resolve-CleanCliProfileState
    if ($profileState.MasterSettings.Count -gt 0) {
        $options = Merge-CleanCliOptions -BaseOptions $options -Overrides $profileState.MasterSettings
    }
    if ($profileState.Mapped -and $profileState.ProfileSettings.Count -gt 0) {
        $options = Merge-CleanCliOptions -BaseOptions $options -Overrides $profileState.ProfileSettings
    }

    $configPath = Find-CleanCliConfigFile -StartPath $StartPath
    if ($configPath -and (Test-Path -LiteralPath $configPath)) {
        $loaded = Import-PowerShellDataFile -LiteralPath $configPath
        $options = Merge-CleanCliOptions -BaseOptions $options -Overrides $loaded
    }
    if (-not $configPath) {
        $configPath = Get-CleanCliUserConfigPath
        if (Test-Path -LiteralPath $configPath) {
            $loaded = Import-PowerShellDataFile -LiteralPath $configPath
            $options = Merge-CleanCliOptions -BaseOptions $options -Overrides $loaded
        }
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

function Get-CleanCliProfile {
    [CmdletBinding()]
    param()

    if (-not $script:CleanCliProfileState.Identifier) { Resolve-CleanCliProfileState | Out-Null }
    if ($script:CleanCliOptions.Count -eq 0) { Initialize-CleanCliOptions | Out-Null }

    [pscustomobject]@{
        Identifier = $script:CleanCliProfileState.Identifier
        ProfileName = $script:CleanCliProfileState.ProfileName
        Mapped = [bool]$script:CleanCliProfileState.Mapped
        ProfilesPath = $script:CleanCliProfileState.ProfilesPath
        MasterSettings = [pscustomobject]$script:CleanCliProfileState.MasterSettings
        ProfileSettings = [pscustomobject]$script:CleanCliProfileState.ProfileSettings
        ConfigPath = $script:CleanCliConfigPath
        FinalSettings = [pscustomobject]$script:CleanCliOptions
    }
}

function New-CleanCliMachineProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [switch]$Force
    )

    $ProfileName = $ProfileName.Trim()
    if (-not $ProfileName) {
        throw 'ProfileName cannot be blank.'
    }

    $profilesPath = Get-CleanCliProfilesPath
    $data = Read-CleanCliProfilesFile -Path $profilesPath
    $identifier = Get-CleanCliMachineIdentifier
    $identifierKey = Get-CleanCliDictionaryKey -Dictionary $data.Identifiers -Key $identifier
    $profileKey = Get-CleanCliDictionaryKey -Dictionary $data.Profiles -Key $ProfileName
    if (-not $profileKey) {
        $profileKey = $ProfileName
        $data.Profiles[$profileKey] = [ordered]@{}
    }

    if ($identifierKey) {
        $existingProfileKey = Get-CleanCliDictionaryKey -Dictionary $data.Profiles -Key $data.Identifiers[$identifierKey]
        if (-not $existingProfileKey) {
            $existingProfileKey = $data.Identifiers[$identifierKey]
        }

        if ((ConvertTo-CleanCliProfileKey -Value $existingProfileKey) -ne (ConvertTo-CleanCliProfileKey -Value $profileKey) -and -not $Force) {
            throw "Machine identifier '$identifier' already maps to profile '$existingProfileKey'. Use -Force to overwrite it."
        }

        $data.Identifiers[$identifierKey] = $profileKey
    }
    else {
        $data.Identifiers[$identifier] = $profileKey
    }

    Save-CleanCliProfilesFile -Path $profilesPath -Data $data
    $script:CleanCliOptions = [ordered]@{}
    Initialize-CleanCliOptions | Out-Null

    Get-CleanCliProfile
}

function Set-CleanCliMachineProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    $ProfileName = $ProfileName.Trim()
    if (-not $ProfileName) {
        throw 'ProfileName cannot be blank.'
    }

    $profilesPath = Get-CleanCliProfilesPath
    if (-not (Test-Path -LiteralPath $profilesPath)) {
        throw "CleanCli profiles file does not exist at '$profilesPath'."
    }

    $data = Read-CleanCliProfilesFile -Path $profilesPath
    $profileKey = Get-CleanCliDictionaryKey -Dictionary $data.Profiles -Key $ProfileName
    if (-not $profileKey) {
        throw "CleanCli profile '$ProfileName' does not exist."
    }

    $identifier = Get-CleanCliMachineIdentifier
    $identifierKey = Get-CleanCliDictionaryKey -Dictionary $data.Identifiers -Key $identifier
    if ($identifierKey) {
        $data.Identifiers[$identifierKey] = $profileKey
    }
    else {
        $data.Identifiers[$identifier] = $profileKey
    }

    Save-CleanCliProfilesFile -Path $profilesPath -Data $data
    $script:CleanCliOptions = [ordered]@{}
    Initialize-CleanCliOptions | Out-Null

    Get-CleanCliProfile
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
    if ($Name -eq 'IconMode' -or $Name -eq 'AsciiMode') {
        Set-CleanCliIconAliases
    }

    [pscustomobject]$script:CleanCliOptions
}
