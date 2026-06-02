@{
    RootModule = 'CleanCli.psm1'
    ModuleVersion = '0.1.0'
    GUID = '8f9d13e4-0e8d-4fd6-9a12-5f1a9db15f47'
    Author = 'David Longnecker'
    CompanyName = 'CleanCli'
    Copyright = '(c) 2026 David Longnecker. All rights reserved.'
    Description = 'Offline native PowerShell prompt and zsh-style PSReadLine setup.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Enable-CleanCli',
        'Disable-CleanCli',
        'Get-CleanCliStatus',
        'Measure-CleanCliStartup',
        'Get-CleanCliOption',
        'Set-CleanCliOption',
        'Get-CleanCliChildItem',
        'Get-CleanCliIconDiagnostics',
        'Set-CleanCliLocation',
        'Get-CleanCliLocationHistory',
        'Open-CleanCliExplorer',
        'Show-CleanCliGitLog',
        'Install-CleanCli'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FormatsToProcess = @('CleanCli.format.ps1xml')
}
