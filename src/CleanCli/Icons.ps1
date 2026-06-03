function Get-CleanCliIconMode {
    $options = Get-CleanCliOption
    if ($options.IconMode -eq 'native' -and ($options.AsciiMode -or $env:CLEANCLI_ASCII -eq '1')) {
        return 'ascii'
    }

    if ($options.IconMode -eq 'terminal-icons' -and (Test-CleanCliNerdFontAvailable)) {
        return 'native'
    }

    $options.IconMode
}

function Test-CleanCliNerdFontName {
    param([string]$Name)

    if (-not $Name) {
        return $false
    }

    [bool]($Name -match '(?i)(nerd\s*font|caskaydia|cascadia.*nf|meslo.*nf|fira.*nerd|jetbrains.*nerd)')
}

function Get-CleanCliWindowsTerminalSettingsPath {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
    )

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    $null
}

function Test-CleanCliWindowsTerminalNerdFont {
    if (-not $env:WT_SESSION) {
        return $false
    }

    $settingsPath = Get-CleanCliWindowsTerminalSettingsPath
    if (-not $settingsPath) {
        return $false
    }

    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    }
    catch {
        return $false
    }

    $defaultFont = $settings.profiles.defaults.font.face
    if (Test-CleanCliNerdFontName -Name $defaultFont) {
        return $true
    }

    $profileId = $env:WT_PROFILE_ID
    if (-not $profileId -or -not $settings.profiles.list) {
        return $false
    }

    foreach ($profile in $settings.profiles.list) {
        if ($profile.guid -eq $profileId -and (Test-CleanCliNerdFontName -Name $profile.font.face)) {
            return $true
        }
    }

    $false
}

function Test-CleanCliNerdFontAvailable {
    if ($env:CLEANCLI_ASCII -eq '1' -or $env:NO_COLOR) {
        return $false
    }

    if ($env:CLEANCLI_NERD_FONT -match '^(1|true|yes)$') {
        return $true
    }
    if ($env:CLEANCLI_NERD_FONT -match '^(0|false|no)$') {
        return $false
    }

    Test-CleanCliWindowsTerminalNerdFont
}

function Get-CleanCliAliasDefinition {
    param(
        [string]$Name,
        [string]$Scope = 'Global'
    )

    $alias = Get-Alias -Name $Name -Scope $Scope -ErrorAction SilentlyContinue
    if (-not $alias) {
        return ''
    }

    $alias.Definition
}

function Save-CleanCliAlias {
    param([string]$Name)

    if ($script:CleanCliState.OriginalAliases.ContainsKey($Name)) {
        return
    }

    $alias = Get-Alias -Name $Name -ErrorAction SilentlyContinue
    if ($alias) {
        $script:CleanCliState.OriginalAliases[$Name] = [pscustomobject]@{
            Exists = $true
            Definition = $alias.Definition
            Options = $alias.Options
        }
        return
    }

    $script:CleanCliState.OriginalAliases[$Name] = [pscustomobject]@{
        Exists = $false
        Definition = ''
        Options = 'None'
    }
}

function Set-CleanCliIconAliases {
    $iconMode = Get-CleanCliIconMode

    foreach ($name in @('ls', 'dir')) {
        Save-CleanCliAlias -Name $name
        $current = Get-Alias -Name $name -ErrorAction SilentlyContinue
        $options = if ($current) { $current.Options } else { $script:CleanCliState.OriginalAliases[$name].Options }
        Set-Alias -Name $name -Value Get-CleanCliChildItem -Scope Global -Option $options -Force
    }

    $script:CleanCliState.IconAliasesEnabled = $true
}

function Restore-CleanCliIconAliases {
    foreach ($name in $script:CleanCliState.OriginalAliases.Keys) {
        $original = $script:CleanCliState.OriginalAliases[$name]
        if ($original.Exists) {
            Set-Alias -Name $name -Value $original.Definition -Scope Global -Option $original.Options -Force
            continue
        }

        Remove-Item -Path "Alias:\$name" -Force -ErrorAction SilentlyContinue
    }

    $script:CleanCliState.IconAliasesEnabled = $false
    $script:CleanCliState.OriginalAliases = @{}
}

function Test-CleanCliIconGlyphSupported {
    param([string]$Icon)

    if (-not $Icon) {
        return $false
    }

    $codePoint = [int][char]$Icon[0]
    $legacyInvalidCodePoints = @(
        0xf5e7
        0xfbc9
        0xfcbe
        0xf832
        0xf872
    )

    $codePoint -notin $legacyInvalidCodePoints
}

function Get-CleanCliIconDiagnostics {
    [CmdletBinding()]
    param()

    $options = Get-CleanCliOption
    $settingsPath = Get-CleanCliWindowsTerminalSettingsPath
    [pscustomobject]@{
        ConfiguredIconMode = $options.IconMode
        EffectiveIconMode = Get-CleanCliIconMode
        AsciiMode = [bool]($options.AsciiMode -or $env:CLEANCLI_ASCII -eq '1')
        NerdFontDetected = Test-CleanCliNerdFontAvailable
        NerdFontOverride = $env:CLEANCLI_NERD_FONT
        WindowsTerminalSession = [bool]$env:WT_SESSION
        WindowsTerminalProfileId = $env:WT_PROFILE_ID
        WindowsTerminalSettingsPath = $settingsPath
        TerminalIconsAvailable = [bool](Get-Module -ListAvailable -Name Terminal-Icons)
        TerminalIconsLoaded = [bool](Get-Module -Name Terminal-Icons)
        IconAliasesEnabled = [bool]$script:CleanCliState.IconAliasesEnabled
        LsDefinition = Get-CleanCliAliasDefinition -Name 'ls'
        DirDefinition = Get-CleanCliAliasDefinition -Name 'dir'
        RecommendedListingCommand = 'Get-CleanCliChildItem'
    }
}

function Get-CleanCliNativeIcon {
    param(
        [System.IO.FileSystemInfo]$Item,
        [object]$Metadata
    )

    if ($Item.PSIsContainer) {
        if ($Metadata -and $Metadata.IsGitRepository) {
            return [string][char]0xf1d3
        }

        $directoryIcons = @{
            '.cache' = [string][char]0xf013
            '.config' = [string][char]0xe615
            '.docker' = [string][char]0xe7b0
            '.vscode' = [string][char]0xe70c
            '.vscode-insiders' = [string][char]0xe70c
            'contacts' = [string][char]0xf0c0
            'desktop' = [string][char]0xf108
            'documents' = [string][char]0xf15c
            'downloads' = [string][char]0xf019
            'favorites' = [string][char]0xf005
            'links' = [string][char]0xf0c1
            'music' = [string][char]0xf001
        }
        $key = $Item.Name.ToLowerInvariant()
        if ($directoryIcons.ContainsKey($key)) {
            $icon = $directoryIcons[$key]
            if (Test-CleanCliIconGlyphSupported -Icon $icon) {
                return $icon
            }
        }

        return [string][char]0xf07b
    }

    switch ([System.IO.Path]::GetExtension($Item.Name).ToLowerInvariant()) {
        '.ps1' { [string][char]0xe795 }
        '.psm1' { [string][char]0xe795 }
        '.psd1' { [string][char]0xe795 }
        '.md' { [string][char]0xf48a }
        '.json' { [string][char]0xe60b }
        '.gitignore' { [string][char]0xe702 }
        default { [string][char]0xf15b }
    }
}

function Get-CleanCliAsciiIcon {
    param(
        [System.IO.FileSystemInfo]$Item,
        [object]$Metadata
    )

    if ($Item.PSIsContainer) {
        if ($Metadata -and $Metadata.IsGitRepository) {
            return '[G]'
        }

        return '[D]'
    }

    '[F]'
}

function ConvertTo-CleanCliAnsiColor {
    param([string]$Hex)

    if (-not $Hex -or $Hex.Length -ne 6) {
        return ''
    }

    try {
        $red = [convert]::ToInt32($Hex.Substring(0, 2), 16)
        $green = [convert]::ToInt32($Hex.Substring(2, 2), 16)
        $blue = [convert]::ToInt32($Hex.Substring(4, 2), 16)
        return "$([char]27)[38;2;${red};${green};${blue}m"
    }
    catch {
        return ''
    }
}

function Get-CleanCliDirectoryGitColor {
    param([object]$Metadata)

    if (-not $Metadata -or -not $Metadata.IsGitRepository) {
        return ''
    }

    switch ($Metadata.StatusState) {
        'clean' { return ConvertTo-CleanCliAnsiColor -Hex '7CFF9B' }
        'pending' { return ConvertTo-CleanCliAnsiColor -Hex 'FFD166' }
        'dirty' { return ConvertTo-CleanCliAnsiColor -Hex 'FF6B6B' }
    }

    ConvertTo-CleanCliAnsiColor -Hex '7DD3FC'
}

function Get-CleanCliIconColor {
    param(
        [System.IO.FileSystemInfo]$Item,
        [object]$Metadata
    )

    if ($env:NO_COLOR) {
        return ''
    }

    if ($Item.PSIsContainer) {
        $gitColor = Get-CleanCliDirectoryGitColor -Metadata $Metadata
        if ($gitColor) {
            return $gitColor
        }

        $directoryColors = @{
            '.cache' = '87ECAF'
            '.config' = '87CEAF'
            '.docker' = '2391E6'
            '.vscode' = '87CEFA'
            '.vscode-insiders' = '24BFA5'
            'contacts' = '00FBFF'
            'desktop' = '00FBFF'
            'documents' = '00BFFF'
            'downloads' = 'D3D3D3'
            'favorites' = 'F7D72C'
            'links' = 'FF143C'
            'music' = 'DB7093'
            'src' = '00FF7F'
            'projects' = '00FF7F'
        }
        $key = $Item.Name.ToLowerInvariant()
        if ($directoryColors.ContainsKey($key)) {
            return ConvertTo-CleanCliAnsiColor -Hex $directoryColors[$key]
        }

        return ConvertTo-CleanCliAnsiColor -Hex 'D3D3D3'
    }

    $wellKnownFileColors = @{
        '.gitignore' = 'FF4500'
        'README' = '00FFFF'
        'README.md' = '00FFFF'
        'README.txt' = '00FFFF'
        'LICENSE' = 'CD5C5C'
        'LICENSE.md' = 'CD5C5C'
        'LICENSE.txt' = 'CD5C5C'
    }
    if ($wellKnownFileColors.ContainsKey($Item.Name)) {
        return ConvertTo-CleanCliAnsiColor -Hex $wellKnownFileColors[$Item.Name]
    }

    $extensionColors = @{
        '.ps1' = '00BFFF'
        '.psm1' = '00BFFF'
        '.psd1' = '00BFFF'
        '.md' = '00BFFF'
        '.json' = 'FFD700'
        '.xml' = '98FB98'
        '.txt' = '00CED1'
        '.exe' = '00FA9A'
        '.dll' = '87CEEB'
        '.pdb' = 'FFD700'
        '.config' = '6495ED'
    }
    $extension = [System.IO.Path]::GetExtension($Item.Name).ToLowerInvariant()
    if ($extensionColors.ContainsKey($extension)) {
        return ConvertTo-CleanCliAnsiColor -Hex $extensionColors[$extension]
    }

    ConvertTo-CleanCliAnsiColor -Hex 'D3D3D3'
}

function Format-CleanCliDirectoryGitDetails {
    param([object]$Metadata)

    if (-not $Metadata -or -not $Metadata.IsGitRepository -or -not $Metadata.Branch) {
        return ''
    }

    $parts = @($Metadata.Branch)
    if ($Metadata.StatusState -in @('clean', 'pending', 'dirty')) {
        if ($Metadata.Ahead -gt 0) {
            $parts += "ahead $($Metadata.Ahead)"
        }
        if ($Metadata.Behind -gt 0) {
            $parts += "behind $($Metadata.Behind)"
        }
        if ($Metadata.StatusSummary) {
            $parts += $Metadata.StatusSummary
        }
    }

    '[' + ($parts -join ' ') + ']'
}

function ConvertTo-CleanCliIconItem {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$IconMode,
        [object]$Metadata
    )

    $icon = if ($IconMode -eq 'ascii') {
        Get-CleanCliAsciiIcon -Item $Item -Metadata $Metadata
    }
    else {
        Get-CleanCliNativeIcon -Item $Item -Metadata $Metadata
    }
    $name = $Item.Name
    $gitDetails = Format-CleanCliDirectoryGitDetails -Metadata $Metadata
    if ($gitDetails) {
        $name = '{0} {1}' -f $Item.Name, $gitDetails
    }
    $plainDisplayName = "$icon  $name"
    $color = Get-CleanCliIconColor -Item $Item -Metadata $Metadata
    $displayName = if ($color) {
        "$color$plainDisplayName$([char]27)[0m"
    }
    else {
        $plainDisplayName
    }

    $result = [pscustomobject]@{
        Mode = $Item.Mode
        LastWriteTime = $Item.LastWriteTime
        Length = if ($Item.PSIsContainer) { $null } else { $Item.Length }
        Icon = $icon
        Name = $Item.Name
        GitBranch = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.Branch } else { '' }
        IsGitRepository = [bool]($Metadata -and $Metadata.IsGitRepository)
        MetadataSource = if ($Metadata) { $Metadata.DataSource } else { '' }
        GitStatusState = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.StatusState } else { '' }
        GitStatusSummary = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.StatusSummary } else { '' }
        GitAhead = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.Ahead } else { 0 }
        GitBehind = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.Behind } else { 0 }
        GitStatusDurationMilliseconds = if ($Metadata -and $Metadata.IsGitRepository) { $Metadata.GitStatusDurationMilliseconds } else { 0 }
        DisplayName = $displayName
        FullName = $Item.FullName
    }
    $result.PSObject.TypeNames.Insert(0, 'CleanCli.IconItem')
    $result
}

function Invoke-CleanCliTerminalIconsChildItem {
    param(
        [string]$Path,
        [switch]$Force,
        [object]$Query
    )

    if (-not (Get-Command Format-TerminalIcons -ErrorAction SilentlyContinue)) {
        if (Get-Module -ListAvailable -Name Terminal-Icons) {
            Import-Module Terminal-Icons -ErrorAction SilentlyContinue
        }
    }

    if (Get-Command Format-TerminalIcons -ErrorAction SilentlyContinue) {
        $items = if ($Force) {
            @(Get-ChildItem -LiteralPath $Path -Force)
        }
        else {
            @(Get-ChildItem -LiteralPath $Path)
        }
        return (Invoke-CleanCliListingQuery -Items $items -Query $Query) | Format-TerminalIcons
    }

    $items = if ($Force) {
        @(Get-ChildItem -LiteralPath $Path -Force)
    }
    else {
        @(Get-ChildItem -LiteralPath $Path)
    }
    Invoke-CleanCliListingQuery -Items $items -Query $Query | ForEach-Object {
        ConvertTo-CleanCliIconItem -Item $_ -IconMode native
    }
}

function Get-CleanCliChildItem {
    [CmdletBinding()]
    param(
        [string]$Path = '.',
        [switch]$Force,
        [switch]$File,
        [switch]$Directory,
        [switch]$Symlink,
        [switch]$Empty,
        [switch]$NonEmpty,
        [string]$ModifiedWithin,
        [string]$ModifiedBefore,
        [string]$AccessedWithin,
        [string]$AccessedBefore,
        [string]$LargerThan,
        [string]$SmallerThan,
        [string]$NameLike,
        [string[]]$Extension,
        [ValidateSet('name', 'size', 'modified', 'accessed')]
        [string]$Sort,
        [switch]$Descending,
        [int]$First,
        [int]$Last,
        [string]$Qualifier
    )

    $input = Resolve-CleanCliListingInput -Path $Path -Qualifier $Qualifier
    $Path = $input.Path
    $Qualifier = $input.Qualifier

    $query = New-CleanCliListingQuery `
        -File:$File `
        -Directory:$Directory `
        -Symlink:$Symlink `
        -Empty:$Empty `
        -NonEmpty:$NonEmpty `
        -ModifiedWithin $ModifiedWithin `
        -ModifiedBefore $ModifiedBefore `
        -AccessedWithin $AccessedWithin `
        -AccessedBefore $AccessedBefore `
        -LargerThan $LargerThan `
        -SmallerThan $SmallerThan `
        -NameLike $NameLike `
        -Extension $Extension `
        -Sort $Sort `
        -Descending:$Descending `
        -First $First `
        -Last $Last `
        -Qualifier $Qualifier

    $iconMode = Get-CleanCliIconMode
    if ($iconMode -eq 'disabled') {
        if ($query.HasCriteria) {
            $items = if ($Force) {
                @(Get-ChildItem -LiteralPath $Path -Force)
            }
            else {
                @(Get-ChildItem -LiteralPath $Path)
            }

            return Invoke-CleanCliListingQuery -Items $items -Query $query
        }

        if ($Force) {
            return Get-ChildItem -LiteralPath $Path -Force
        }

        return Get-ChildItem -LiteralPath $Path
    }

    if ($iconMode -eq 'terminal-icons') {
        return Invoke-CleanCliTerminalIconsChildItem -Path $Path -Force:$Force -Query $query
    }

    Receive-CleanCliDirectoryReadAhead
    $items = if ($Force) {
        @(Get-ChildItem -LiteralPath $Path -Force)
    }
    else {
        @(Get-ChildItem -LiteralPath $Path)
    }

    $filteredItems = Invoke-CleanCliListingQuery -Items $items -Query $query
    $result = foreach ($item in $filteredItems) {
        $metadata = $null
        if ($item.PSIsContainer) {
            $metadata = Get-CleanCliDirectoryMetadataForPath -Path $item.FullName
        }

        ConvertTo-CleanCliIconItem -Item $item -IconMode $iconMode -Metadata $metadata
    }

    Start-CleanCliDirectoryReadAhead -Path $Path
    return $result
}
