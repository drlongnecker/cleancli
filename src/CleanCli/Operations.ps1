function Get-CleanCliHostName {
    if ($env:CODEX_THREAD_ID) {
        return 'Codex'
    }

    if ($env:TERM_PROGRAM -eq 'vscode') {
        return 'VSCode'
    }

    if ($env:WT_SESSION) {
        return 'WindowsTerminal'
    }

    'PlainConsole'
}

function Test-CleanCliHostEnabled {
    param([string]$HostName = (Get-CleanCliHostName))

    $options = Get-CleanCliOption
    switch ($HostName) {
        'Codex' { return [bool]$options.EnableInCodex }
        'VSCode' { return [bool]$options.EnableInVSCode }
        'WindowsTerminal' { return [bool]$options.EnableInWindowsTerminal }
        default { return [bool]$options.EnableInPlainConsole }
    }
}

function Install-CleanCli {
    [CmdletBinding()]
    param(
        [string]$Destination
    )

    if (-not $Destination) {
        $modulesRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
        $Destination = Join-Path $modulesRoot 'CleanCli'
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $script:CleanCliRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }

    [pscustomobject]@{
        Source = $script:CleanCliRoot
        Destination = [System.IO.Path]::GetFullPath($Destination)
    }
}
