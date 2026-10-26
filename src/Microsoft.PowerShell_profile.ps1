if ($env:CLEANCLI_DISABLE -ne '1') {
    if ($env:CLEANCLI_INTERACTIVE_ONLY -eq '0' -or -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
        $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $OutputEncoding
        [Console]::OutputEncoding = $OutputEncoding

        $cleanCliModule = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'src\CleanCli\CleanCli.psd1'
        if (Test-Path -LiteralPath $cleanCliModule) {
            Import-Module $cleanCliModule -Force
            Enable-CleanCli
        }
    }
}

if ($env:TERM_PROGRAM -eq 'vscode') {
    $__vscodeIntegrationPath = code --locate-shell-integration-path pwsh 2>$null
    if ($__vscodeIntegrationPath -and (Test-Path -LiteralPath $__vscodeIntegrationPath)) {
        . $__vscodeIntegrationPath
    }
    Remove-Variable __vscodeIntegrationPath -ErrorAction SilentlyContinue
}
