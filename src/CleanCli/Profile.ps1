if ($env:CLEANCLI_DISABLE -eq '1') {
    return
}

if ($env:CLEANCLI_INTERACTIVE_ONLY -ne '0' -and ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
    return
}
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $OutputEncoding
[Console]::OutputEncoding = $OutputEncoding

$modulePath = Join-Path $PSScriptRoot 'CleanCli.psd1'
Import-Module $modulePath -Force
Enable-CleanCli
