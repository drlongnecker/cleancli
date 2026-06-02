function Get-CleanCliIconMode {
    $options = Get-CleanCliOption
    if ($options.IconMode -eq 'native' -and ($options.AsciiMode -or $env:CLEANCLI_ASCII -eq '1')) {
        return 'ascii'
    }

    $options.IconMode
}

function Get-CleanCliNativeIcon {
    param([System.IO.FileSystemInfo]$Item)

    if ($Item.PSIsContainer) {
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
    param([System.IO.FileSystemInfo]$Item)

    if ($Item.PSIsContainer) {
        return '[D]'
    }

    '[F]'
}

function ConvertTo-CleanCliIconItem {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$IconMode
    )

    $icon = if ($IconMode -eq 'ascii') {
        Get-CleanCliAsciiIcon -Item $Item
    }
    else {
        Get-CleanCliNativeIcon -Item $Item
    }

    [pscustomobject]@{
        Mode = $Item.Mode
        LastWriteTime = $Item.LastWriteTime
        Length = if ($Item.PSIsContainer) { $null } else { $Item.Length }
        Icon = $icon
        Name = $Item.Name
        DisplayName = "$icon $($Item.Name)"
        FullName = $Item.FullName
    }
}

function Invoke-CleanCliTerminalIconsChildItem {
    param(
        [string]$Path,
        [switch]$Force
    )

    if (-not (Get-Command Format-TerminalIcons -ErrorAction SilentlyContinue)) {
        if (Get-Module -ListAvailable -Name Terminal-Icons) {
            Import-Module Terminal-Icons -ErrorAction SilentlyContinue
        }
    }

    if (Get-Command Format-TerminalIcons -ErrorAction SilentlyContinue) {
        if ($Force) {
            return Get-ChildItem -LiteralPath $Path -Force | Format-TerminalIcons
        }

        return Get-ChildItem -LiteralPath $Path | Format-TerminalIcons
    }

    if ($Force) {
        return Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
            ConvertTo-CleanCliIconItem -Item $_ -IconMode native
        }
    }

    Get-ChildItem -LiteralPath $Path | ForEach-Object {
        ConvertTo-CleanCliIconItem -Item $_ -IconMode native
    }
}

function Get-CleanCliChildItem {
    [CmdletBinding()]
    param(
        [string]$Path = '.',
        [switch]$Force
    )

    $iconMode = Get-CleanCliIconMode
    if ($iconMode -eq 'disabled') {
        if ($Force) {
            return Get-ChildItem -LiteralPath $Path -Force
        }

        return Get-ChildItem -LiteralPath $Path
    }

    if ($iconMode -eq 'terminal-icons') {
        return Invoke-CleanCliTerminalIconsChildItem -Path $Path -Force:$Force
    }

    if ($Force) {
        return Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
            ConvertTo-CleanCliIconItem -Item $_ -IconMode $iconMode
        }
    }

    Get-ChildItem -LiteralPath $Path | ForEach-Object {
        ConvertTo-CleanCliIconItem -Item $_ -IconMode $iconMode
    }
}
