param(
    [string]$RawBaseUrl = 'https://raw.githubusercontent.com/drlongnecker/cleancli/main/src/CleanCli',
    [string]$ProfilePath = $PROFILE,
    [string]$ModulesPath,
    [switch]$NoProfilePrompt
)

$ErrorActionPreference = 'Stop'

$moduleName = 'CleanCli'
$moduleFiles = @(
    'CleanCli.format.ps1xml',
    'CleanCli.psd1',
    'CleanCli.psm1',
    'Config.ps1',
    'DirectoryCache.ps1',
    'Git.ps1',
    'GitCompletion.ps1',
    'Icons.ps1',
    'Listing.ps1',
    'Navigation.ps1',
    'Operations.ps1',
    'Profile.ps1',
    'Prompt.ps1',
    'PSReadLine.ps1'
)

function Resolve-CleanCliModulesPath {
    param(
        [string]$Path,
        [string]$CurrentProfilePath
    )

    if ($Path) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if (-not $CurrentProfilePath) {
        throw 'PowerShell did not report a current profile path.'
    }

    $profileDirectory = Split-Path -Path $CurrentProfilePath -Parent
    if (-not $profileDirectory) {
        throw "Could not resolve a directory from profile path '$CurrentProfilePath'."
    }

    [System.IO.Path]::GetFullPath((Join-Path $profileDirectory 'Modules'))
}

function Test-CleanCliDirectoryAccess {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Out-Null

    $probePath = Join-Path $Path ".cleancli-write-test-$([guid]::NewGuid().ToString('N'))"
    try {
        Set-Content -LiteralPath $probePath -Value 'write-test' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop
    }
    catch {
        throw "Current user does not have read/write access to '$Path'. $($_.Exception.Message)"
    }
}

function Save-CleanCliModuleFiles {
    param(
        [string]$BaseUrl,
        [string]$Destination
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "cleancli-install-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        foreach ($fileName in $moduleFiles) {
            $sourceUri = "$($BaseUrl.TrimEnd('/'))/$fileName"
            $targetPath = Join-Path $tempRoot $fileName
            Write-Host "Downloading $fileName"
            Invoke-WebRequest -Uri $sourceUri -OutFile $targetPath -UseBasicParsing
        }

        if (-not (Test-Path -LiteralPath $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }

        foreach ($fileName in $moduleFiles) {
            Copy-Item -LiteralPath (Join-Path $tempRoot $fileName) -Destination (Join-Path $Destination $fileName) -Force
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Add-CleanCliProfileImport {
    param(
        [string]$Path,
        [string]$ModuleManifestPath
    )

    $profileDirectory = Split-Path -Path $Path -Parent
    if ($profileDirectory -and -not (Test-Path -LiteralPath $profileDirectory)) {
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $profileText = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($profileText -and $profileText -match 'Import-Module\s+.*CleanCli\.psd1') {
        Write-Host "CleanCli already appears in '$Path'. Profile was not changed."
        return
    }

    $backupPath = "$Path.cleancli-backup-$((Get-Date).ToString('yyyyMMddHHmmss'))"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    $escapedModuleManifestPath = $ModuleManifestPath.Replace("'", "''")
    $block = @"

# CleanCli
if (`$env:CLEANCLI_DISABLE -ne '1') {
    if (`$env:CLEANCLI_INTERACTIVE_ONLY -eq '0' -or -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
        Import-Module '$escapedModuleManifestPath' -Force
        Enable-CleanCli
    }
}
"@

    Add-Content -LiteralPath $Path -Value $block -Encoding UTF8
    Write-Host "Profile backup created at '$backupPath'."
}

$resolvedModulesPath = Resolve-CleanCliModulesPath -Path $ModulesPath -CurrentProfilePath $ProfilePath
Test-CleanCliDirectoryAccess -Path $resolvedModulesPath

$moduleDestination = Join-Path $resolvedModulesPath $moduleName
$moduleManifestPath = Join-Path $moduleDestination 'CleanCli.psd1'
$alreadyInstalled = Test-Path -LiteralPath $moduleManifestPath

Save-CleanCliModuleFiles -BaseUrl $RawBaseUrl -Destination $moduleDestination

if ($alreadyInstalled) {
    Write-Host "CleanCli was already installed. Updated files in '$moduleDestination'."
    return
}

Write-Host "CleanCli installed to '$moduleDestination'."

if ($NoProfilePrompt) {
    Write-Host "Profile autoload prompt was skipped."
    return
}

$answer = Read-Host "Auto-load CleanCli from '$ProfilePath' in new PowerShell sessions? (y/n)"
if ($answer -match '^(y|yes)$') {
    Add-CleanCliProfileImport -Path $ProfilePath -ModuleManifestPath $moduleManifestPath
    Write-Host "CleanCli autoload was added to '$ProfilePath'."
}
else {
    Write-Host "Profile was not changed. You can load CleanCli manually with: Import-Module '$moduleManifestPath' -Force; Enable-CleanCli"
}
