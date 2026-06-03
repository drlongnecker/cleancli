function Get-CleanCliLocationHistoryPath {
    if ($env:CLEANCLI_LOCATION_HISTORY_PATH) {
        return [System.IO.Path]::GetFullPath($env:CLEANCLI_LOCATION_HISTORY_PATH)
    }

    $configPath = Get-CleanCliUserConfigPath
    Join-Path (Split-Path -Parent $configPath) 'CleanCli.location-history.json'
}

function Get-CleanCliLocationHistory {
    [CmdletBinding()]
    param()

    $path = Get-CleanCliLocationHistoryPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }

    $items = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    @($items) | Sort-Object LastVisitedUtc -Descending
}

function Save-CleanCliLocationHistory {
    param([object[]]$History)

    $path = Get-CleanCliLocationHistoryPath
    $directory = Split-Path -Parent $path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    @($History | Select-Object -First 100) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $path -Encoding ASCII
}

function Add-CleanCliLocationHistory {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $now = [datetime]::UtcNow.ToString('o')
    $history = @(Get-CleanCliLocationHistory | Where-Object { $_.Path -ne $fullPath })
    $entry = [pscustomobject]@{
        Path = $fullPath
        LastVisitedUtc = $now
    }

    Save-CleanCliLocationHistory -History @($entry; $history)
}

function Find-CleanCliLocationHistoryMatch {
    param([string]$Query)

    $queryText = $Query.ToLowerInvariant()
    Get-CleanCliLocationHistory |
        Where-Object { $_.Path.ToLowerInvariant().Contains($queryText) } |
        Sort-Object @{
            Expression = {
                $leaf = Split-Path -Leaf $_.Path
                if ($leaf.ToLowerInvariant().StartsWith($queryText)) { 0 }
                elseif ($leaf.ToLowerInvariant().Contains($queryText)) { 1 }
                else { 2 }
            }
        }, LastVisitedUtc |
        Select-Object -First 1
}

function Set-CleanCliLocation {
    [CmdletBinding()]
    param([string]$Path = '~')

    $target = if (Test-Path -LiteralPath $Path -PathType Container) {
        [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
    }
    else {
        $match = Find-CleanCliLocationHistoryMatch -Query $Path
        if (-not $match) {
            throw "No directory matches '$Path'."
        }
        $match.Path
    }

    Set-Location -LiteralPath $target
    Add-CleanCliLocationHistory -Path $target
    Start-CleanCliDirectoryReadAhead -Path $target
}

function Open-CleanCliExplorer {
    [CmdletBinding()]
    param([string]$Path = (Get-Location).ProviderPath)

    explorer $Path
}

function Show-CleanCliGitLog {
    [CmdletBinding()]
    param([string]$Path)

    $arguments = @('log', '--graph', '--decorate', '--stat', '--pretty=format:%C(auto)%h %d %s%n%C(green)%ad %C(blue)%an%n', '--date=short')
    if ($Path) {
        $arguments += $Path
    }

    git @arguments
}
