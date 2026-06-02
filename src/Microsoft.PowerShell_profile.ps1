if ($env:CLEANCLI_DISABLE -eq '1') {
    return
}

if ($env:CLEANCLI_INTERACTIVE_ONLY -ne '0' -and ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
    return
}

if ($env:TERM_PROGRAM -eq 'vscode') {
    $integrationPath = code --locate-shell-integration-path pwsh
    if ($integrationPath) {
        . $integrationPath
    }
}

$OutputEncoding = [System.Text.Encoding]::UTF8

function log([string] $path) {
    git log --graph --decorate --stat --pretty=format:"%C(auto)%h %d %s%n%C(green)%ad %C(blue)%an%n" --date=short $path
}

function e {
    explorer .
}

$cleanCliModule = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src\CleanCli\CleanCli.psd1'
if (Test-Path -LiteralPath $cleanCliModule) {
    Import-Module $cleanCliModule -Force
    Enable-CleanCli
}
