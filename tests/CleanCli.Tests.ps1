$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ProjectRoot 'src\CleanCli\CleanCli.psd1'
$ProfilePath = Join-Path $ProjectRoot 'src\Microsoft.PowerShell_profile.ps1'
$InstallerPath = Join-Path $ProjectRoot 'installer.ps1'

Describe 'CleanCli profile bootstrap' {
    It 'does not load online or slow prompt dependencies' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Not Match 'import-module\s+posh-git'
        $profileText | Should Not Match 'import-module\s+mklink'
        $profileText | Should Not Match 'oh-my-posh'
    }

    It 'does not import Terminal-Icons eagerly during profile startup' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Not Match 'Import-Module\s+Terminal-Icons'
    }

    It 'contains a CleanCli disable gate' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Match 'CLEANCLI_DISABLE'
        $profileText | Should Match 'Enable-CleanCli'
    }

    It 'does not define legacy helper functions outside the module' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Not Match 'function\s+log\b'
        $profileText | Should Not Match 'function\s+e\b'
    }
}

Describe 'CleanCli installer script' {
    It 'parses as valid PowerShell' {
        $tokens = $null
        $errors = $null

        [System.Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$tokens, [ref]$errors) | Out-Null

        $errors.Count | Should Be 0
    }

    It 'downloads the complete module file set from GitHub raw content' {
        $installerText = Get-Content -LiteralPath $InstallerPath -Raw

        $installerText | Should Match 'https://raw\.githubusercontent\.com/drlongnecker/cleancli/main/src/CleanCli'
        foreach ($fileName in @(
            'CleanCli.format.ps1xml',
            'CleanCli.psd1',
            'CleanCli.psm1',
            'Config.ps1',
            'DirectoryCache.ps1',
            'Git.ps1',
            'Icons.ps1',
            'Listing.ps1',
            'Navigation.ps1',
            'Operations.ps1',
            'Profile.ps1',
            'Prompt.ps1',
            'PSReadLine.ps1'
        )) {
            $installerText | Should Match ([regex]::Escape("'$fileName'"))
        }
    }

    It 'updates existing installs without adding profile autoload' {
        $installerText = Get-Content -LiteralPath $InstallerPath -Raw

        $installerText | Should Match '\$alreadyInstalled = Test-Path'
        $installerText | Should Match 'if \(\$alreadyInstalled\)'
        $installerText | Should Match 'Profile autoload prompt was skipped'
    }

    It 'backs up the current profile before appending CleanCli autoload' {
        $installerText = Get-Content -LiteralPath $InstallerPath -Raw

        $installerText | Should Match 'cleancli-backup'
        $installerText | Should Match 'Add-Content -LiteralPath \$Path'
        $installerText | Should Match "Import-Module '\`$escapedModuleManifestPath' -Force"
        $installerText | Should Match 'Enable-CleanCli'
    }
}

Describe 'CleanCli module behavior' {
    BeforeAll {
        if (Get-Module CleanCli) {
            Remove-Module CleanCli -Force
        }
        Import-Module $ModulePath -Force
    }

    AfterAll {
        if (Get-Module CleanCli) {
            Remove-Module CleanCli -Force
        }
    }

    It 'exports the planned public commands' {
        $commands = Get-Command -Module CleanCli | Select-Object -ExpandProperty Name

        ($commands -contains 'Enable-CleanCli') | Should Be $true
        ($commands -contains 'Disable-CleanCli') | Should Be $true
        ($commands -contains 'Get-CleanCliStatus') | Should Be $true
        ($commands -contains 'Measure-CleanCliStartup') | Should Be $true
        ($commands -contains 'Get-CleanCliIconDiagnostics') | Should Be $true
        ($commands -contains 'Get-CleanCliOption') | Should Be $true
        ($commands -contains 'Set-CleanCliOption') | Should Be $true
        ($commands -contains 'Get-CleanCliChildItem') | Should Be $true
        ($commands -contains 'Set-CleanCliLocation') | Should Be $true
        ($commands -contains 'Get-CleanCliLocationHistory') | Should Be $true
        ($commands -contains 'Open-CleanCliExplorer') | Should Be $true
        ($commands -contains 'Show-CleanCliGitLog') | Should Be $true
        ($commands -contains 'Install-CleanCli') | Should Be $true
        ($commands -contains 'Get-CleanCliProfile') | Should Be $true
        ($commands -contains 'New-CleanCliMachineProfile') | Should Be $true
        ($commands -contains 'Set-CleanCliMachineProfile') | Should Be $true
    }

    It 'returns default CleanCli options' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'missing.config.psd1'
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
            }
            $options = Get-CleanCliOption

            $options.GitTimeoutMilliseconds | Should Be 1000
            $options.GitCacheMilliseconds | Should Be 750
            $options.GitUntrackedMode | Should Be 'normal'
            $options.GitIgnoreSubmodules | Should Be 'none'
            $options.GitStatusMode | Should Be 'full'
            $options.GitDivergenceMode | Should Be 'none'
            $options.DirectoryReadAheadMode | Should Be 'metadata'
            $options.DirectoryReadAheadDepth | Should Be 1
            $options.DirectoryMetadataCacheMilliseconds | Should Be 5000
            $options.DirectoryReadAheadMaxDirectories | Should Be 64
            $options.DirectoryReadAheadDebounceMilliseconds | Should Be 250
            $options.DirectoryAlwaysShowGitBranches | Should Be $true
            $options.DirectoryGitStatusMode | Should Be 'disabled'
            $options.PathDisplayMode | Should Be 'auto'
            $options.PromptLayout | Should Be 'single'
            $options.IconMode | Should Be 'native'
            $options.CommandDurationThresholdMilliseconds | Should Be 2000
            $options.RightPrompt | Should Be $false
            $options.PromptSeparator | Should Be 'auto'
            $options.PathSymbol | Should Be 'auto'
            $options.GitSymbol | Should Be 'auto'
            $options.DirtySymbol | Should Be 'auto'
            $options.AdminSymbol | Should Be 'auto'
            $options.TimeSymbol | Should Be 'auto'
            $options.AdminForeground | Should Be 'Yellow'
            $options.AdminBackground | Should Be 'Black'
            $options.PathForeground | Should Be 'White'
            $options.PathBackground | Should Be 'Magenta'
            $options.GitForeground | Should Be 'Black'
            $options.GitBackground | Should Be 'Green'
            $options.TimeForeground | Should Be 'Black'
            $options.TimeBackground | Should Be 'Yellow'
            $options.KeyBindingPreset | Should Be 'zsh'
            $options.EnableInCodex | Should Be $true
            $options.EnableInVSCode | Should Be $true
            $options.EnableInWindowsTerminal | Should Be $true
            $options.EnableInPlainConsole | Should Be $true
            $options.AsciiMode | Should Be $false
            $options.TransientPrompt | Should Be $false
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'sets and returns a CleanCli option' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name GitTimeoutMilliseconds -Value 250 | Out-Null

                Get-CleanCliOption -Name GitTimeoutMilliseconds | Should Be 250
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'persists a CleanCli option to the config file' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name TransientPrompt -Value $true | Out-Null
                Test-Path -LiteralPath $env:CLEANCLI_CONFIG_PATH | Should Be $true

                $script:CleanCliOptions = [ordered]@{}
                $loaded = Initialize-CleanCliOptions
                $loaded.TransientPrompt | Should Be $true
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'loads CleanCli.config.psd1 from a supplied start path' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $child = Join-Path $tempRoot 'child'
        New-Item -ItemType Directory -Path $child | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'CleanCli.config.psd1') -Value "@{ GitTimeoutMilliseconds = 333; AsciiMode = `$true }" -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_CONFIG_PATH = $child
            InModuleScope CleanCli {
                $loaded = Initialize-CleanCliOptions -StartPath $env:CLEANCLI_TEST_CONFIG_PATH
                $loaded.GitTimeoutMilliseconds | Should Be 333
                $loaded.AsciiMode | Should Be $true
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'loads the user CleanCli config when no project config exists' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $documentsRoot = Join-Path $tempRoot 'Documents'
        $configRoot = Join-Path $documentsRoot 'PowerShell'
        $startPath = Join-Path $tempRoot 'NoProjectConfig'
        New-Item -ItemType Directory -Path $configRoot | Out-Null
        New-Item -ItemType Directory -Path $startPath | Out-Null
        Set-Content -LiteralPath (Join-Path $configRoot 'CleanCli.config.psd1') -Value "@{ IconMode = 'terminal-icons' }" -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_START_PATH = $startPath
            InModuleScope CleanCli {
                $script:CleanCliUserConfigPathOverride = Join-Path (Join-Path (Split-Path -Parent $env:CLEANCLI_TEST_START_PATH) 'Documents\PowerShell') 'CleanCli.config.psd1'
                try {
                    $loaded = Initialize-CleanCliOptions -StartPath $env:CLEANCLI_TEST_START_PATH

                    $loaded.IconMode | Should Be 'terminal-icons'
                }
                finally {
                    $script:CleanCliUserConfigPathOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_START_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'loads master and matched machine profile settings before project config' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $projectRoot = Join-Path $tempRoot 'project'
        New-Item -ItemType Directory -Path $projectRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        $configPath = Join-Path $projectRoot 'CleanCli.config.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{
        IconMode = 'native'
        GitStatusMode = 'branch'
    }
    Identifiers = @{
        'joyeuse.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{
            GitStatusMode = 'async'
            RightPrompt = `$true
        }
    }
}
"@ -Encoding ASCII
        Set-Content -LiteralPath $configPath -Value "@{ RightPrompt = `$false }" -Encoding ASCII
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_TEST_START_PATH = $projectRoot
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'JOYEUSE.david'
                try {
                    $loaded = Initialize-CleanCliOptions -StartPath $env:CLEANCLI_TEST_START_PATH

                    $loaded.IconMode | Should Be 'native'
                    $loaded.GitStatusMode | Should Be 'async'
                    $loaded.RightPrompt | Should Be $false
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_START_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'maps multiple identifiers to one reusable profile' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{}
    Identifiers = @{
        'srv1.david' = 'vm'
        'srv2.david' = 'vm'
    }
    Profiles = @{
        vm = @{
            IconMode = 'ascii'
            GitStatusMode = 'branch'
        }
    }
}
"@ -Encoding ASCII
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_TEST_START_PATH = $tempRoot
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'SRV2.david'
                $script:CleanCliUserConfigPathOverride = Join-Path $env:CLEANCLI_TEST_START_PATH 'missing.user.config.psd1'
                $tempRoot = $env:CLEANCLI_TEST_START_PATH
                try {
                    $loaded = Initialize-CleanCliOptions -StartPath $tempRoot

                    $loaded.IconMode | Should Be 'ascii'
                    $loaded.GitStatusMode | Should Be 'branch'
                    $profile = Get-CleanCliProfile
                    $profile.Identifier | Should Be 'SRV2.david'
                    $profile.ProfileName | Should Be 'vm'
                    $profile.Mapped | Should Be $true
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                    $script:CleanCliUserConfigPathOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_START_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps environment overrides after profile and project settings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $projectRoot = Join-Path $tempRoot 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        $configPath = Join-Path $projectRoot 'CleanCli.config.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{
        AsciiMode = `$false
    }
    Identifiers = @{
        'joyeuse.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{
            AsciiMode = `$false
        }
    }
}
"@ -Encoding ASCII
        Set-Content -LiteralPath $configPath -Value "@{ AsciiMode = `$false }" -Encoding ASCII
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH
        $hadCleanCliAscii = Test-Path Env:\CLEANCLI_ASCII
        $originalCleanCliAscii = $env:CLEANCLI_ASCII

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_TEST_START_PATH = $projectRoot
            $env:CLEANCLI_ASCII = '1'
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'JOYEUSE.david'
                try {
                    $loaded = Initialize-CleanCliOptions -StartPath $env:CLEANCLI_TEST_START_PATH

                    $loaded.AsciiMode | Should Be $true
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_START_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliAscii) {
                $env:CLEANCLI_ASCII = $originalCleanCliAscii
            }
            else {
                Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            }
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'creates a machine profile mapping' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'WORKSTATION.david'
                try {
                    { New-CleanCliMachineProfile -ProfileName '   ' } | Should Throw 'ProfileName cannot be blank.'

                    $profile = New-CleanCliMachineProfile -ProfileName 'desktop'

                    $profile.Identifier | Should Be 'WORKSTATION.david'
                    $profile.ProfileName | Should Be 'desktop'
                    $profile.Mapped | Should Be $true
                    Test-Path -LiteralPath $env:CLEANCLI_PROFILES_PATH | Should Be $true

                    $data = Import-PowerShellDataFile -LiteralPath $env:CLEANCLI_PROFILES_PATH
                    $data.Identifiers['WORKSTATION.david'] | Should Be 'desktop'
                    $data.Profiles.Contains('desktop') | Should Be $true
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'refuses to overwrite a machine mapping without Force' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{}
    Identifiers = @{
        'WORKSTATION.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{}
        laptop = @{}
    }
}
"@ -Encoding ASCII

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'workstation.DAVID'
                try {
                    { New-CleanCliMachineProfile -ProfileName 'laptop' } | Should Throw 'already maps to profile'

                    $data = Import-PowerShellDataFile -LiteralPath $env:CLEANCLI_PROFILES_PATH
                    $data.Identifiers['WORKSTATION.david'] | Should Be 'desktop'

                    $profile = New-CleanCliMachineProfile -ProfileName 'laptop' -Force
                    $profile.ProfileName | Should Be 'laptop'

                    $data = Import-PowerShellDataFile -LiteralPath $env:CLEANCLI_PROFILES_PATH
                    $data.Identifiers['WORKSTATION.david'] | Should Be 'laptop'
                    @($data.Identifiers.Keys | Where-Object { $_ -ceq 'workstation.DAVID' }).Count | Should Be 0
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'remaps only to an existing profile' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{}
    Identifiers = @{
        'WORKSTATION.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{}
        laptop = @{
            GitStatusMode = 'branch'
        }
    }
}
"@ -Encoding ASCII

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'workstation.DAVID'
                try {
                    { Set-CleanCliMachineProfile -ProfileName '   ' } | Should Throw 'ProfileName cannot be blank.'
                    { Set-CleanCliMachineProfile -ProfileName 'missing' } | Should Throw "profile 'missing' does not exist"

                    $profile = Set-CleanCliMachineProfile -ProfileName 'laptop'
                    $profile.ProfileName | Should Be 'laptop'
                    $profile.Mapped | Should Be $true
                    $profile.ProfileSettings.GitStatusMode | Should Be 'branch'

                    $data = Import-PowerShellDataFile -LiteralPath $env:CLEANCLI_PROFILES_PATH
                    $data.Identifiers['WORKSTATION.david'] | Should Be 'laptop'
                    $data.Profiles.Contains('missing') | Should Be $false
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'throws instead of dropping unknown machine profile settings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{
        NotARealOption = 'kept'
    }
    Identifiers = @{}
    Profiles = @{}
}
"@ -Encoding ASCII

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'WORKSTATION.david'
                try {
                    { New-CleanCliMachineProfile -ProfileName 'desktop' } | Should Throw "Unknown CleanCli option 'NotARealOption'"
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'rejects invalid values in machine profile settings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{}
    Identifiers = @{
        'WORKSTATION.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{
            GitStatusMode = 'broken'
        }
    }
}
"@ -Encoding ASCII

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'WORKSTATION.david'
                try {
                    { Initialize-CleanCliOptions -StartPath $env:TEMP } | Should Throw 'GitStatusMode must be one of: full, branch, async.'
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'does not invoke git.exe in a non-git directory' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCommand = {
                    throw 'git should not be called outside a repository'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $info.IsRepository | Should Be $false
                $info.GitInvoked | Should Be $false
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'parses the branch from a .git HEAD file without git.exe' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/feature/offline-prompt' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCommand = {
                    throw 'branch parsing should not need git.exe'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH -SkipStatus
                $info.IsRepository | Should Be $true
                $info.Branch | Should Be 'feature/offline-prompt'
                $info.GitInvoked | Should Be $false
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'ignores a .git file that points at a missing git directory' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot '.git') -Value 'gitdir: .git\missing-worktree' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCommand = {
                    throw 'invalid gitdir should not invoke git status'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $info.IsRepository | Should Be $false
                $info.GitInvoked | Should Be $false
                $info.DataSource | Should Be 'none'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves linked worktree git directories from a .git file' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $worktree = Join-Path $tempRoot 'worktree'
        $gitDir = Join-Path $tempRoot '.git\worktrees\worktree'
        New-Item -ItemType Directory -Path $worktree | Out-Null
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $worktree '.git') -Value 'gitdir: ..\.git\worktrees\worktree' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/worktree-branch' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $worktree
            InModuleScope CleanCli {
                $script:CleanCliGitCommand = {
                    throw 'branch-only worktree inspection should not invoke git status'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH -SkipStatus

                $info.IsRepository | Should Be $true
                $info.Branch | Should Be 'worktree-branch'
                $info.GitInvoked | Should Be $false
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'recognizes a bare repository directory without invoking git status for branch-only data' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'objects') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'refs') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'HEAD') -Value 'ref: refs/heads/bare-main' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'config') -Value "[core]`n    bare = true" -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCommand = {
                    throw 'bare branch-only inspection should not invoke git status'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH -SkipStatus

                $info.IsRepository | Should Be $true
                $info.Root | Should Be $env:CLEANCLI_TEST_PATH
                $info.GitDir | Should Be $env:CLEANCLI_TEST_PATH
                $info.Branch | Should Be 'bare-main'
                $info.GitInvoked | Should Be $false
                $info.DataSource | Should Be 'branch-only'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'suppresses full git status after repeated timeout events' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliGitCommand = {
                    return $null
                }

                $first = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $second = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $third = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $first.GitInvoked | Should Be $true
                $second.GitInvoked | Should Be $true
                $third.GitInvoked | Should Be $false
                $third.GitSuppressed | Should Be $true
                $third.Branch | Should Be 'main'
                $script:CleanCliState.LastGitProcessCount | Should Be 0
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps the last successful git counts when later status calls time out' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliSlowGitRepositories = @{}
                $script:CleanCliGitCalls = 0
                $script:CleanCliGitCommand = {
                    $script:CleanCliGitCalls++
                    if ($script:CleanCliGitCalls -eq 1) {
                        return " M changed-1.txt`n M changed-2.txt`nA  staged.txt"
                    }

                    return $null
                }

                $first = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $second = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $third = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $fourth = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $first.Dirty | Should Be $true
                $first.Working | Should Be 2
                $first.Staged | Should Be 1
                $second.TimedOut | Should Be $true
                $second.Dirty | Should Be $true
                $second.Working | Should Be 2
                $second.Staged | Should Be 1
                $second.DataSource | Should Be 'last-successful'
                $third.TimedOut | Should Be $true
                $third.Dirty | Should Be $true
                $third.Working | Should Be 2
                $third.Staged | Should Be 1
                $fourth.GitSuppressed | Should Be $true
                $fourth.Dirty | Should Be $true
                $fourth.Working | Should Be 2
                $fourth.Staged | Should Be 1
                $fourth.DataSource | Should Be 'last-successful'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'records the last git command duration after successful status' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliGitCommand = {
                    Start-Sleep -Milliseconds 20
                    "## main"
                }

                Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH | Out-Null
                $status = Get-CleanCliStatus

                [bool]($status.LastGitDurationMilliseconds -gt 0) | Should Be $true
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'marks cached git status data in diagnostics' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 10000
                $script:CleanCliGitCalls = 0
                $script:CleanCliGitCommand = {
                    $script:CleanCliGitCalls++
                    " M changed.txt"
                }

                $first = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $second = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $first.DataSource | Should Be 'full'
                $second.DataSource | Should Be 'cached'
                $second.GitInvoked | Should Be $false
                $script:CleanCliGitCalls | Should Be 1
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses local git status counts without branch divergence by default' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliLastGitArguments = $null
                $script:CleanCliGitCommand = {
                    param($RepositoryRoot, $Arguments)
                    $script:CleanCliLastGitArguments = $Arguments
                    " M changed.txt`nA  staged.txt`n?? new.txt"
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                ($script:CleanCliLastGitArguments -contains '--branch') | Should Be $false
                ($script:CleanCliLastGitArguments -contains '--no-optional-locks') | Should Be $true
                ($script:CleanCliLastGitArguments -contains '-c') | Should Be $true
                ($script:CleanCliLastGitArguments -contains 'core.quotepath=false') | Should Be $true
                ($script:CleanCliLastGitArguments -contains 'color.status=false') | Should Be $true
                ($script:CleanCliLastGitArguments -contains '--porcelain=v1') | Should Be $true
                ($script:CleanCliLastGitArguments -contains '--untracked-files=normal') | Should Be $true
                ($script:CleanCliLastGitArguments -contains '--ignore-submodules=none') | Should Be $true
                $info.Branch | Should Be 'main'
                $info.Working | Should Be 1
                $info.Staged | Should Be 1
                $info.Untracked | Should Be 1
                $info.Ahead | Should Be 0
                $info.Behind | Should Be 0
                $info.DataSource | Should Be 'full'
                $info.CacheKey | Should Not Be $null
                $info.GitArguments | Should Be ($script:CleanCliLastGitArguments -join ' ')
                $info.SuppressionCount | Should Be 0
                $info.SuppressionThreshold | Should Be 2
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'parses git status into Oh My Posh style change counters' {
        InModuleScope CleanCli {
            $status = Convert-CleanCliGitStatus -StatusText "?? untracked.txt`nA  staged-added.txt`n M working-modified.txt`nD  staged-deleted.txt`n D working-deleted.txt`nR  old.txt -> new.txt`nUU conflicted.txt"

            $status.Untracked | Should Be 1
            $status.Added | Should Be 1
            $status.Modified | Should Be 1
            $status.Deleted | Should Be 2
            $status.Moved | Should Be 1
            $status.Unmerged | Should Be 1
            $status.StatusSummary | Should Be '?1 +1 ~1 -2 >1 x1'
        }
    }

    It 'renders git prompt changes using Oh My Posh style status formatting' {
        InModuleScope CleanCli {
            $oldAscii = $env:CLEANCLI_ASCII
            try {
                $env:CLEANCLI_ASCII = '1'
                $git = [pscustomobject]@{
                    IsRepository = $true
                    Branch = 'main'
                    Dirty = $true
                    Ahead = 0
                    Behind = 0
                    Working = 3
                    Staged = 3
                    Untracked = 1
                    Added = 1
                    Modified = 1
                    Deleted = 2
                    Moved = 1
                    Unmerged = 1
                    Conflicted = 0
                    Missing = 0
                    Clean = 0
                    Ignored = 0
                    StatusSummary = '?1 +1 ~1 -2 >1 x1'
                    TimedOut = $false
                }

                Get-CleanCliGitPromptText -Git $git | Should Be 'git: main * ?1 +1 ~1 -2 >1 x1'
            }
            finally {
                $env:CLEANCLI_ASCII = $oldAscii
            }
        }
    }

    It 'uses branch-only mode without invoking git status' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name GitStatusMode -Value branch | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'branch mode should not invoke git status'
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $info.Branch | Should Be 'main'
                $info.GitInvoked | Should Be $false
                $info.DataSource | Should Be 'branch-only'
                $info.Working | Should Be 0
                $info.Staged | Should Be 0
                $info.Untracked | Should Be 0
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders branch-only first and updates cached counts after async git refresh' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            $env:CLEANCLI_TEST_LINK_CREATED = if ($linkCreated) { '1' } else { '0' }
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name GitStatusMode -Value async | Out-Null
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 10000
                $script:CleanCliGitAsyncRefreshes = @{}
                $script:CleanCliGitAsyncCalls = 0
                $script:CleanCliGitCommand = {
                    throw 'async mode should not synchronously invoke git status'
                }
                $script:CleanCliGitAsyncCommand = {
                    $script:CleanCliGitAsyncCalls++
                    " M async-changed.txt`n?? async-new.txt"
                }

                $first = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH
                $second = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                $first.DataSource | Should Be 'branch-only'
                $first.GitInvoked | Should Be $false
                $first.Dirty | Should Be $false
                $second.DataSource | Should Be 'cached'
                $second.Dirty | Should Be $true
                $second.Working | Should Be 1
                $second.Untracked | Should Be 1
                $script:CleanCliGitAsyncCalls | Should Be 1
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'adds branch divergence only when configured' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name GitDivergenceMode -Value local | Out-Null
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliLastGitArguments = $null
                $script:CleanCliGitCommand = {
                    param($RepositoryRoot, $Arguments)
                    $script:CleanCliLastGitArguments = $Arguments
                    "## main...origin/main [ahead 2, behind 1]`n M changed.txt"
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                ($script:CleanCliLastGitArguments -contains '--branch') | Should Be $true
                $info.Ahead | Should Be 2
                $info.Behind | Should Be 1
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses configured git untracked and submodule modes for status' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name GitUntrackedMode -Value no | Out-Null
                Set-CleanCliOption -Name GitIgnoreSubmodules -Value dirty | Out-Null
                $script:CleanCliGitCache = @{}
                $script:CleanCliGitCacheMilliseconds = 0
                $script:CleanCliLastGitArguments = $null
                $script:CleanCliGitCommand = {
                    param($RepositoryRoot, $Arguments)
                    $script:CleanCliLastGitArguments = $Arguments
                    " M changed.txt"
                }

                $info = Get-CleanCliGitInfo -Path $env:CLEANCLI_TEST_PATH

                ($script:CleanCliLastGitArguments -contains '--untracked-files=no') | Should Be $true
                ($script:CleanCliLastGitArguments -contains '--ignore-submodules=dirty') | Should Be $true
                $info.Working | Should Be 1
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'does not render a last command status segment in the prompt' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                Push-Location $env:TEMP
                try {
                    $global:LASTEXITCODE = 7
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Not Match '> ! '
                    $promptText | Should Not Match '> \+ '
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'formats command durations compactly' {
        InModuleScope CleanCli {
            Format-CleanCliCommandDuration -Milliseconds 1500 | Should Be '1.5s'
            Format-CleanCliCommandDuration -Milliseconds 65000 | Should Be '1m 5s'
            Format-CleanCliCommandDuration -Milliseconds 3723000 | Should Be '1h 2m'
        }
    }

    It 'does not render command duration below the configured threshold' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name CommandDurationThresholdMilliseconds -Value 2000 | Out-Null
                $script:CleanCliCommandDurationProvider = { 1500 }
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                Push-Location $env:TEMP
                try {
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Not Match '1\.5s'
                }
                finally {
                    Pop-Location
                    $script:CleanCliCommandDurationProvider = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders command duration when it meets the configured threshold' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name CommandDurationThresholdMilliseconds -Value 1000 | Out-Null
                $script:CleanCliCommandDurationProvider = { 1500 }
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                Push-Location $env:TEMP
                try {
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Match 'time: 1\.5s'
                }
                finally {
                    Pop-Location
                    $script:CleanCliCommandDurationProvider = $null
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'formats a right prompt with ANSI cursor positioning' {
        InModuleScope CleanCli {
            $escape = [char]27
            $right = Format-CleanCliRightPrompt -LeftText 'left ' -RightText 'right' -Width 20

            $right | Should Be "$escape[s$escape[16Gright$escape[u"
        }
    }

    It 'renders git status on the right when right prompt is enabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = $null
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name RightPrompt -Value $true | Out-Null
                $script:CleanCliGitCommand = {
                    ''
                }
                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    $promptText = Invoke-CleanCliPrompt
                    $escape = [char]27

                    $promptText | Should Match ([regex]::Escape("$escape[s"))
                    $promptText | Should Match 'git: main'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps git status on the left when right prompt is enabled but color is disabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $gitDir = Join-Path $tempRoot '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name RightPrompt -Value $true | Out-Null
                $script:CleanCliGitCommand = {
                    ''
                }
                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    $promptText = Invoke-CleanCliPrompt
                    $escape = [char]27

                    $promptText | Should Not Match ([regex]::Escape("$escape[s"))
                    $promptText | Should Match 'git: main'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'compacts long home paths while preserving root and leaf context' {
        InModuleScope CleanCli {
            $home = [Environment]::GetFolderPath('UserProfile')
            $path = Join-Path $home 'AppData\Roaming\cleancli-launcher\blob_storage\09064e10-8a6c-4c30-972c-f8980ebcfe86'

            $short = Get-CleanCliShortPath -Path $path

            $short | Should Be '~\AppData\...\blob_storage\09064e10...'
        }
    }

    It 'renders Powerline bridge separators with adjacent segment colors' {
        InModuleScope CleanCli {
            $oldNoColor = $env:NO_COLOR
            $oldAscii = $env:CLEANCLI_ASCII
            try {
                $env:NO_COLOR = $null
                $env:CLEANCLI_ASCII = $null
                $script:CleanCliOptions.AsciiMode = $false
                $segments = @(
                    New-CleanCliSegment -Text 'dir: ~\src' -Foreground Black -Background Blue
                    New-CleanCliSegment -Text 'git: main' -Foreground Black -Background Yellow
                )

                $promptText = Format-CleanCliPromptSegments -Segments $segments
                $escape = [char]27

                $promptText.Contains(('{0}[30;44m dir: ~\src {0}[0m' -f $escape)) | Should Be $true
                $promptText.Contains(('{0}[34;43m{0}[0m' -f $escape)) | Should Be $true
                $promptText.Contains(('{0}[30;43m git: main {0}[0m' -f $escape)) | Should Be $true
                $promptText.Contains(('{0}[33;49m{0}[0m ' -f $escape)) | Should Be $true
            }
            finally {
                $env:NO_COLOR = $oldNoColor
                $env:CLEANCLI_ASCII = $oldAscii
            }
        }
    }

    It 'renders an explicit two-line prompt layout' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name PromptLayout -Value 'two-line' | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                Push-Location $env:TEMP
                try {
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Match "`n> $"
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses a two-line prompt automatically when the rendered prompt is long' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $longPath = Join-Path $tempRoot 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\cccccccccccccccccccccccccccccccccccccccc'
        New-Item -ItemType Directory -Path $longPath | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            $env:CLEANCLI_TEST_LONG_PATH = $longPath
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name PromptLayout -Value 'auto' | Out-Null
                Set-CleanCliOption -Name PathDisplayMode -Value 'full' | Out-Null
                $script:CleanCliGitCommand = {
                    ''
                }
                Push-Location $env:CLEANCLI_TEST_LONG_PATH
                try {
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Match "`n> $"
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_LONG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses ASCII symbols when CLEANCLI_ASCII is set' {
        InModuleScope CleanCli {
            $oldValue = $env:CLEANCLI_ASCII
            try {
                $env:CLEANCLI_ASCII = '1'
                $symbols = Get-CleanCliSymbols
                $symbols.Separator | Should Be '>'
                $symbols.Branch | Should Be 'git:'
            }
            finally {
                $env:CLEANCLI_ASCII = $oldValue
            }
        }
    }

    It 'uses configured ASCII symbols without requiring CLEANCLI_ASCII' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                $oldValue = $env:CLEANCLI_ASCII
                try {
                    $env:CLEANCLI_ASCII = $null
                    Initialize-CleanCliOptions | Out-Null
                    Set-CleanCliOption -Name AsciiMode -Value $true | Out-Null
                    $symbols = Get-CleanCliSymbols
                    $symbols.Separator | Should Be '>'
                    $symbols.Branch | Should Be 'git:'
                    Set-CleanCliOption -Name AsciiMode -Value $false | Out-Null
                }
                finally {
                    $env:CLEANCLI_ASCII = $oldValue
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses configured prompt symbol overrides' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name AsciiMode -Value $true | Out-Null
                Set-CleanCliOption -Name PromptSeparator -Value '|' | Out-Null
                Set-CleanCliOption -Name PathSymbol -Value 'cwd:' | Out-Null
                Set-CleanCliOption -Name GitSymbol -Value 'branch:' | Out-Null
                Set-CleanCliOption -Name DirtySymbol -Value 'dirty' | Out-Null
                Set-CleanCliOption -Name AdminSymbol -Value 'root' | Out-Null
                Set-CleanCliOption -Name TimeSymbol -Value 't:' | Out-Null

                $symbols = Get-CleanCliSymbols

                $symbols.Separator | Should Be '|'
                $symbols.Path | Should Be 'cwd:'
                $symbols.Branch | Should Be 'branch:'
                $symbols.Dirty | Should Be 'dirty'
                $symbols.Admin | Should Be 'root'
                $symbols.Time | Should Be 't:'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses configured prompt segment colors' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = $null
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name PathForeground -Value Black | Out-Null
                Set-CleanCliOption -Name PathBackground -Value Cyan | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                Push-Location $env:TEMP
                try {
                    $promptText = Invoke-CleanCliPrompt
                    $escape = [char]27

                    $promptText | Should Match ([regex]::Escape("$escape[30;46m"))
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'maps configurable prompt colors to ANSI foreground and background codes' {
        InModuleScope CleanCli {
            Get-CleanCliAnsiCode -Color Default | Should Be 39
            Get-CleanCliAnsiCode -Color DarkGray | Should Be 90
            Get-CleanCliAnsiCode -Color White -Background | Should Be 47
            Get-CleanCliAnsiCode -Color Default -Background | Should Be 49
        }
    }

    It 'builds the admin indicator from configured text and colors' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name AdminSymbol -Value elevated | Out-Null
                Set-CleanCliOption -Name AdminForeground -Value Red | Out-Null
                Set-CleanCliOption -Name AdminBackground -Value Yellow | Out-Null

                $segment = New-CleanCliAdminSegment

                $segment.Text | Should Be 'elevated'
                $segment.Foreground | Should Be 'Red'
                $segment.Background | Should Be 'Yellow'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'defines zsh-like key bindings with substring history search and menu completion' {
        InModuleScope CleanCli {
            $bindings = Get-CleanCliKeyBindingsForPreset -Preset zsh

            ($bindings | Where-Object { $_.Key -eq 'Tab' }).Function | Should Be 'MenuComplete'
            ($bindings | Where-Object { $_.Key -eq 'UpArrow' }).Function | Should Be $null
            ($bindings | Where-Object { $_.Key -eq 'UpArrow' }).ScriptBlock | Should Not Be $null
            ($bindings | Where-Object { $_.Key -eq 'UpArrow' }).Description | Should Match 'cursor at the end'
            ($bindings | Where-Object { $_.Key -eq 'DownArrow' }).Function | Should Be $null
            ($bindings | Where-Object { $_.Key -eq 'DownArrow' }).ScriptBlock | Should Not Be $null
            ($bindings | Where-Object { $_.Key -eq 'DownArrow' }).Description | Should Match 'cursor at the end'
            ($bindings | Where-Object { $_.Key -eq 'RightArrow' }).Function | Should Be 'ForwardChar'
            ($bindings | Where-Object { $_.Key -eq 'RightArrow' }).ScriptBlock | Should Be $null
        }
    }

    It 'installs editable history and cursor navigation key handlers' {
        if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'PSReadLine is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name KeyBindingPreset -Value zsh | Out-Null
                Set-CleanCliPSReadLine
            }

            (Get-PSReadLineKeyHandler -Key RightArrow).Function | Should Be 'ForwardChar'
            (Get-PSReadLineKeyHandler -Key UpArrow).Function | Should Be 'CustomAction'
            (Get-PSReadLineKeyHandler -Key UpArrow).Description | Should Match 'cursor at the end'
            (Get-PSReadLineKeyHandler -Key DownArrow).Function | Should Be 'CustomAction'
            (Get-PSReadLineKeyHandler -Key DownArrow).Description | Should Match 'cursor at the end'
        }
        finally {
            InModuleScope CleanCli {
                Restore-CleanCliPSReadLine
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'defines minimal key bindings without overriding navigation keys' {
        InModuleScope CleanCli {
            $bindings = Get-CleanCliKeyBindingsForPreset -Preset minimal

            ($bindings | Where-Object { $_.Key -eq 'UpArrow' }) | Should Be $null
            ($bindings | Where-Object { $_.Key -eq 'DownArrow' }) | Should Be $null
            ($bindings | Where-Object { $_.Key -eq 'Tab' }).Function | Should Be 'MenuComplete'
        }
    }

    It 'records and reuses persistent location history for fuzzy directory jumping' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $projectPath = Join-Path $tempRoot 'alpha-project'
        $otherPath = Join-Path $tempRoot 'other'
        New-Item -ItemType Directory -Path $projectPath | Out-Null
        New-Item -ItemType Directory -Path $otherPath | Out-Null

        try {
            $env:CLEANCLI_LOCATION_HISTORY_PATH = Join-Path $tempRoot 'locations.json'
            Push-Location $otherPath
            try {
                Set-CleanCliLocation -Path $projectPath
                Set-CleanCliLocation -Path $otherPath
                Set-CleanCliLocation -Path alpha

                (Get-Location).ProviderPath | Should Be $projectPath
                (Get-CleanCliLocationHistory | Select-Object -First 1).Path | Should Be $projectPath
            }
            finally {
                Pop-Location
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_LOCATION_HISTORY_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'detects the current host for per-host toggles' {
        InModuleScope CleanCli {
            $oldCodex = $env:CODEX_THREAD_ID
            $oldTermProgram = $env:TERM_PROGRAM
            $oldWtSession = $env:WT_SESSION
            try {
                $env:CODEX_THREAD_ID = 'test'
                Get-CleanCliHostName | Should Be 'Codex'

                Remove-Item Env:\CODEX_THREAD_ID -ErrorAction SilentlyContinue
                $env:TERM_PROGRAM = 'vscode'
                Get-CleanCliHostName | Should Be 'VSCode'

                Remove-Item Env:\TERM_PROGRAM -ErrorAction SilentlyContinue
                $env:WT_SESSION = 'test'
                Get-CleanCliHostName | Should Be 'WindowsTerminal'

                Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
                Get-CleanCliHostName | Should Be 'PlainConsole'
            }
            finally {
                if ($null -eq $oldCodex) { Remove-Item Env:\CODEX_THREAD_ID -ErrorAction SilentlyContinue } else { $env:CODEX_THREAD_ID = $oldCodex }
                if ($null -eq $oldTermProgram) { Remove-Item Env:\TERM_PROGRAM -ErrorAction SilentlyContinue } else { $env:TERM_PROGRAM = $oldTermProgram }
                if ($null -eq $oldWtSession) { Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue } else { $env:WT_SESSION = $oldWtSession }
            }
        }
    }

    It 'skips initialization when the current host is disabled and reports why' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CODEX_THREAD_ID = 'test'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name EnableInCodex -Value $false | Out-Null

                Enable-CleanCli
                $status = Get-CleanCliStatus

                $status.Enabled | Should Be $false
                $status.HostName | Should Be 'Codex'
                $status.LoadStatus | Should Be 'skipped'
                $status.LoadReason | Should Match 'disabled'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CODEX_THREAD_ID -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'reports compact profile diagnostics in CleanCli status' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        Set-Content -LiteralPath $profilesPath -Value @"
@{
    Master = @{}
    Identifiers = @{
        'WORKSTATION.david' = 'desktop'
    }
    Profiles = @{
        desktop = @{}
    }
}
"@ -Encoding ASCII
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'WORKSTATION.david'
                $script:CleanCliProfileState.Identifier = $null
                $script:CleanCliProfileState.ProfileName = $null
                $script:CleanCliProfileState.Mapped = $false
                $script:CleanCliProfileState.ProfilesPath = $null
                $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                try {
                    Initialize-CleanCliOptions | Out-Null
                    $status = Get-CleanCliStatus

                    $status.ProfileIdentifier | Should Be 'WORKSTATION.david'
                    $status.ProfileName | Should Be 'desktop'
                    $status.ProfileMapped | Should Be $true
                    $status.ProfilesPath | Should Be $env:CLEANCLI_PROFILES_PATH
                }
                finally {
                    $script:CleanCliMachineIdentifierOverride = $null
                    $script:CleanCliProfilePromptReader = $null
                    $script:CleanCliProfileState.Identifier = $null
                    $script:CleanCliProfileState.ProfileName = $null
                    $script:CleanCliProfileState.Mapped = $false
                    $script:CleanCliProfileState.ProfilesPath = $null
                    $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                    $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'runs setup prompt for an unmapped interactive machine' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'NEWMACHINE.david'
                $script:CleanCliProfileState.Identifier = $null
                $script:CleanCliProfileState.ProfileName = $null
                $script:CleanCliProfileState.Mapped = $false
                $script:CleanCliProfileState.ProfilesPath = $null
                $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                $answers = [System.Collections.Queue]::new()
                $answers.Enqueue('yes')
                $answers.Enqueue('laptop')
                $script:CleanCliProfilePromptReader = {
                    param([string]$Prompt)
                    $script:CleanCliPromptCalls++
                    $answers.Dequeue()
                }
                $script:CleanCliPromptCalls = 0
                try {
                    Invoke-CleanCliProfileSetupPrompt -InteractiveOverride:$true

                    $script:CleanCliPromptCalls | Should Be 2
                    $profile = Get-CleanCliProfile
                    $profile.Identifier | Should Be 'NEWMACHINE.david'
                    $profile.ProfileName | Should Be 'laptop'
                    $profile.Mapped | Should Be $true
                    Test-Path -LiteralPath $env:CLEANCLI_PROFILES_PATH | Should Be $true
                }
                finally {
                    Disable-CleanCli
                    $script:CleanCliMachineIdentifierOverride = $null
                    $script:CleanCliProfilePromptReader = $null
                    $script:CleanCliPromptCalls = $null
                    $script:CleanCliProfileState.Identifier = $null
                    $script:CleanCliProfileState.ProfileName = $null
                    $script:CleanCliProfileState.Mapped = $false
                    $script:CleanCliProfileState.ProfilesPath = $null
                    $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                    $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'does not create a profile from a blank setup prompt name' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'BLANKNAME.david'
                $script:CleanCliProfileState.Identifier = $null
                $script:CleanCliProfileState.ProfileName = $null
                $script:CleanCliProfileState.Mapped = $false
                $script:CleanCliProfileState.ProfilesPath = $null
                $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                $answers = [System.Collections.Queue]::new()
                $answers.Enqueue('y')
                $answers.Enqueue('   ')
                $script:CleanCliProfilePromptReader = {
                    param([string]$Prompt)
                    $answers.Dequeue()
                }
                try {
                    Invoke-CleanCliProfileSetupPrompt -InteractiveOverride:$true

                    Test-Path -LiteralPath $env:CLEANCLI_PROFILES_PATH | Should Be $false
                    $profile = Get-CleanCliProfile
                    $profile.Mapped | Should Be $false
                    $profile.ProfileName | Should Be $null
                }
                finally {
                    Disable-CleanCli
                    $script:CleanCliMachineIdentifierOverride = $null
                    $script:CleanCliProfilePromptReader = $null
                    $script:CleanCliProfileState.Identifier = $null
                    $script:CleanCliProfileState.ProfileName = $null
                    $script:CleanCliProfileState.Mapped = $false
                    $script:CleanCliProfileState.ProfilesPath = $null
                    $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                    $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'does not prompt for an unmapped non-interactive machine or when prompt is disabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $profilesPath = Join-Path $tempRoot 'CleanCli.profiles.psd1'
        $hadCleanCliConfigPath = Test-Path Env:\CLEANCLI_CONFIG_PATH
        $originalCleanCliConfigPath = $env:CLEANCLI_CONFIG_PATH
        $hadProfilesPrompt = Test-Path Env:\CLEANCLI_PROFILES_PROMPT
        $originalProfilesPrompt = $env:CLEANCLI_PROFILES_PROMPT
        $hadCodexThreadId = Test-Path Env:\CODEX_THREAD_ID
        $originalCodexThreadId = $env:CODEX_THREAD_ID

        try {
            $env:CLEANCLI_PROFILES_PATH = $profilesPath
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                $script:CleanCliOptions = [ordered]@{}
                $script:CleanCliMachineIdentifierOverride = 'UNMAPPED.david'
                $script:CleanCliProfileState.Identifier = $null
                $script:CleanCliProfileState.ProfileName = $null
                $script:CleanCliProfileState.Mapped = $false
                $script:CleanCliProfileState.ProfilesPath = $null
                $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                $script:CleanCliProfilePromptReader = {
                    throw 'profile setup prompt should not run'
                }
                try {
                    Invoke-CleanCliProfileSetupPrompt -InteractiveOverride:$false
                    $env:CLEANCLI_PROFILES_PROMPT = '0'
                    Invoke-CleanCliProfileSetupPrompt -InteractiveOverride:$true
                    Remove-Item Env:\CLEANCLI_PROFILES_PROMPT -ErrorAction SilentlyContinue

                    Test-Path -LiteralPath $env:CLEANCLI_PROFILES_PATH | Should Be $false

                    Initialize-CleanCliOptions | Out-Null
                    Set-CleanCliOption -Name EnableInCodex -Value $false | Out-Null
                    $env:CODEX_THREAD_ID = 'test'
                    Enable-CleanCli
                    $status = Get-CleanCliStatus
                    $status.Enabled | Should Be $false
                    $status.LoadStatus | Should Be 'skipped'
                }
                finally {
                    Disable-CleanCli
                    Remove-Item Env:\CODEX_THREAD_ID -ErrorAction SilentlyContinue
                    $script:CleanCliMachineIdentifierOverride = $null
                    $script:CleanCliProfilePromptReader = $null
                    $script:CleanCliProfileState.Identifier = $null
                    $script:CleanCliProfileState.ProfileName = $null
                    $script:CleanCliProfileState.Mapped = $false
                    $script:CleanCliProfileState.ProfilesPath = $null
                    $script:CleanCliProfileState.MasterSettings = [ordered]@{}
                    $script:CleanCliProfileState.ProfileSettings = [ordered]@{}
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_PROFILES_PATH -ErrorAction SilentlyContinue
            if ($hadCleanCliConfigPath) {
                $env:CLEANCLI_CONFIG_PATH = $originalCleanCliConfigPath
            }
            else {
                Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            }
            if ($hadProfilesPrompt) {
                $env:CLEANCLI_PROFILES_PROMPT = $originalProfilesPrompt
            }
            else {
                Remove-Item Env:\CLEANCLI_PROFILES_PROMPT -ErrorAction SilentlyContinue
            }
            if ($hadCodexThreadId) {
                $env:CODEX_THREAD_ID = $originalCodexThreadId
            }
            else {
                Remove-Item Env:\CODEX_THREAD_ID -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'installs the module to a local destination without network access' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $destination = Join-Path $tempRoot 'CleanCli'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            Install-CleanCli -Destination $destination | Out-Null

            Test-Path -LiteralPath (Join-Path $destination 'CleanCli.psd1') | Should Be $true
            Test-Path -LiteralPath (Join-Path $destination 'CleanCli.psm1') | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'reports startup timing by CleanCli and Terminal-Icons layer' {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwsh) {
            Set-ItResult -Skipped -Because 'pwsh is not available.'
            return
        }

        $timing = Measure-CleanCliStartup -PowerShellPath $pwsh

        $timing.NoProfileMilliseconds | Should Not Be $null
        $timing.CleanCliImportMilliseconds | Should Not Be $null
        $timing.CleanCliEnableMilliseconds | Should Not Be $null
        $timing.TerminalIconsImportMilliseconds | Should Not Be $null
        $timing.CleanCliWithTerminalIconsMilliseconds | Should Not Be $null
        $timing.ForcedProfileLoadMilliseconds | Should Not Be $null
    }

    It 'reports repeated startup timing sample statistics' {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwsh) {
            Set-ItResult -Skipped -Because 'pwsh is not available.'
            return
        }

        $timing = Measure-CleanCliStartup -PowerShellPath $pwsh -Iterations 2

        $timing.Iterations | Should Be 2
        $timing.NoProfileMillisecondsMinimum | Should Not Be $null
        $timing.NoProfileMillisecondsAverage | Should Not Be $null
        $timing.NoProfileMillisecondsMaximum | Should Not Be $null
        $timing.CleanCliEnableMillisecondsMinimum | Should Not Be $null
        $timing.ForcedProfileLoadMillisecondsMaximum | Should Not Be $null
    }

    It 'configures PSReadLine prompt text when transient prompt is enabled' {
        if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'PSReadLine is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $originalPromptText = (Get-PSReadLineOption).PromptText

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name TransientPrompt -Value $true | Out-Null
                Set-CleanCliPSReadLine
            }

            ((Get-PSReadLineOption).PromptText -join '') | Should Be '> '
        }
        finally {
            InModuleScope CleanCli {
                Restore-CleanCliPSReadLine
            }
            if ($null -eq $originalPromptText) {
                Set-PSReadLineOption -PromptText ''
            }
            else {
                Set-PSReadLineOption -PromptText $originalPromptText
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'restores PSReadLine prompt text after transient prompt is disabled' {
        if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'PSReadLine is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $originalPromptText = (Get-PSReadLineOption).PromptText

        try {
            Set-PSReadLineOption -PromptText 'original> '
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name TransientPrompt -Value $true | Out-Null
                Set-CleanCliPSReadLine
                Restore-CleanCliPSReadLine
            }

            ((Get-PSReadLineOption).PromptText -join '') | Should Be 'original> '
        }
        finally {
            if ($null -eq $originalPromptText) {
                Set-PSReadLineOption -PromptText ''
            }
            else {
                Set-PSReadLineOption -PromptText $originalPromptText
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders native offline icons for directory listings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH |
                    Where-Object { $_.Name -in @('src', 'README.md') }

                $folder = $items | Where-Object Name -eq 'src'
                $markdown = $items | Where-Object Name -eq 'README.md'

                $folder.Icon | Should Not Be ''
                $markdown.Icon | Should Not Be ''
                $folder.Name | Should Be 'src'
                $markdown.Name | Should Be 'README.md'
                $folder.DisplayName | Should Match 'src'
                $markdown.DisplayName | Should Match 'README.md'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'filters directory listings by type flags and qualifier tokens' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII
        $linkCreated = $false
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $tempRoot 'readme-link.md') -Target (Join-Path $tempRoot 'README.md') -ErrorAction Stop | Out-Null
            $linkCreated = $true
        }
        catch {
            $linkCreated = $false
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Extension md).Name | Should Be 'README.md'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Directory).Name | Should Be 'src'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.' -Extension md).Name | Should Be 'README.md'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '/').Name | Should Be 'src'

                if ($env:CLEANCLI_TEST_LINK_CREATED -eq '1') {
                    (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Symlink).Name | Should Be 'readme-link.md'
                    (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '@').Name | Should Be 'readme-link.md'
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_LINK_CREATED -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'filters empty and non-empty directories with flags and zsh-style qualifiers' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'empty') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'full') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'full\child.txt') -Value 'child' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'file.txt') -Value 'file' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Directory -Empty).Name | Should Be 'empty'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Directory -NonEmpty).Name | Should Be 'full'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '/^F').Name | Should Be 'empty'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '/F').Name | Should Be 'full'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'treats qualifier-looking positional strings as current-directory filters' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'cleancli') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'cleanclip') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'other') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'clean-file.txt') -Value 'file' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path (Join-Path $env:CLEANCLI_TEST_PATH 'cleancli')).Count | Should Be 0
                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    (Get-CleanCliChildItem '/clea*' | Sort-Object Name).Name -join ',' | Should Be 'cleancli,cleanclip'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'treats PowerShell-style wildcard arguments as listing name filters' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'xi') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'folder.exe') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot '.config') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'app.exe') -Value 'app' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot '.profile') -Value 'profile' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'xip.txt') -Value 'xip' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'note.txt') -Value 'note' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    (Get-CleanCliChildItem xi).Count | Should Be 0
                    (Get-CleanCliChildItem xi* | Sort-Object Name).Name -join ',' | Should Be 'xi,xip.txt'
                    (Get-CleanCliChildItem *.exe | Sort-Object Name).Name -join ',' | Should Be 'app.exe'
                    (Get-CleanCliChildItem .* | Sort-Object Name).Name -join ',' | Should Be '.profile,app.exe,CleanCli.config.psd1,note.txt,xip.txt'
                    (Get-CleanCliChildItem ..* | Sort-Object Name).Name -join ',' | Should Be '.profile'
                    (Get-CleanCliChildItem /.* | Sort-Object Name).Name -join ',' | Should Be '.config'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'supports explicit and implicit qualifiers beyond directory filtering' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'recent.txt') -Value 'recent' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'old.txt') -Value 'old' -Encoding ASCII
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastAccessTime = (Get-Date).AddDays(-5)

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.a+2').Name | Should Be 'old.txt'
                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    (Get-CleanCliChildItem '.a+2').Name | Should Be 'old.txt'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'combines file and directory type qualifiers with later filters' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $oldDir = Join-Path $tempRoot 'old-dir'
        $newDir = Join-Path $tempRoot 'new-dir'
        New-Item -ItemType Directory -Path $oldDir | Out-Null
        New-Item -ItemType Directory -Path $newDir | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'old.txt') -Value 'old' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'new.txt') -Value 'new' -Encoding ASCII
        (Get-Item -LiteralPath $oldDir).LastAccessTime = (Get-Date).AddDays(-5)
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastAccessTime = (Get-Date).AddDays(-5)

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier './a+2' | Sort-Object Name).Name -join ',' | Should Be 'old-dir,old.txt'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'treats trailing qualifier-looking text as a name glob when it is not a valid token' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot '.config') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot '.empty') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'normal') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot '.config\settings.json') -Value '{}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot '.dot-file') -Value 'file' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'module.ps1') -Value 'module' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '/F.*').Name | Should Be '.config'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '..*').Name | Should Be '.dot-file'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.module*').Name | Should Be 'module.ps1'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'filters directory listings by modified, accessed, and size shortcuts' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'recent.txt') -Value 'recent' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'old.txt') -Value 'old' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'large.bin') -Value ('x' * 2048) -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'tiny.bin') -Value 'x' -Encoding ASCII
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastAccessTime = (Get-Date).AddDays(-10)

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -ModifiedWithin 7d -NameLike '*.txt').Name | Should Be 'recent.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -ModifiedBefore 7d).Name | Should Be 'old.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Qualifier '.m-7' -NameLike '*.txt').Name | Should Be 'recent.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Qualifier '.m+7').Name | Should Be 'old.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Qualifier '.mm-30' -NameLike 'recent.txt').Name | Should Be 'recent.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Qualifier '.m-70m' -NameLike 'recent.txt').Name | Should Be 'recent.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -AccessedBefore 7d).Name | Should Be 'old.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -LargerThan 1kb -NameLike '*.bin').Name | Should Be 'large.bin'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -SmallerThan 10b -NameLike '*.bin' | Sort-Object Name).Name -join ',' | Should Be 'tiny.bin'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.L+1k' -NameLike '*.bin').Name | Should Be 'large.bin'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.L-10' -NameLike '*.bin' | Sort-Object Name).Name -join ',' | Should Be 'tiny.bin'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'filters recursive listings with compact qualifiers' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'logs') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'logs\small.log') -Value 'small' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'src\large.txt') -Value 'large' -Encoding ASCII
        $largeStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'logs\large.log'))
        try {
            $largeStream.SetLength(101KB)
        }
        finally {
            $largeStream.Dispose()
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Recurse -Qualifier '.L+100k*.log'

                $items.Count | Should Be 1
                $items[0].Name | Should Be 'large.log'
                $items[0].PSObject.TypeNames[0] | Should Not Be 'CleanCli.IconItem'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'applies recursive directory selectors to the intended directory level' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tmp-root') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'test\tmp') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'something\tmp2') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'other') | Out-Null
        foreach ($name in @('tmp-root\root.log', 'test\tmp\nested.log', 'something\tmp2\deep.log', 'other\skip.log')) {
            $stream = [System.IO.File]::OpenWrite((Join-Path $tempRoot $name))
            try {
                $stream.SetLength(101KB)
            }
            finally {
                $stream.Dispose()
            }
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                $topLevel = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Recurse -RecurseDirectory 'tmp*' -Qualifier '.L+100k*.log'
                $anyLevel = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Recurse -RecurseDirectory '*/tmp*' -Qualifier '.L+100k*.log' | Sort-Object Name

                $topLevel.Name | Should Be 'root.log'
                ($anyLevel.Name -join ',') | Should Be 'deep.log,nested.log,root.log'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses the second recursive positional argument as the item filter' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tmp-root') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'test\tmp') | Out-Null
        $rootStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'tmp-root\root.log'))
        $nestedStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'test\tmp\nested.log'))
        try {
            $rootStream.SetLength(101KB)
            $nestedStream.SetLength(101KB)
        }
        finally {
            $rootStream.Dispose()
            $nestedStream.Dispose()
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    (Get-CleanCliChildItem -r '*/tmp*' '.L+100k*.log' | Sort-Object Name).Name -join ',' | Should Be 'nested.log,root.log'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'parses every documented listing qualifier example in the README' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'cleancli') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'cleanclip') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot '.config') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot '.profile') -Value 'profile' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'src\child.txt') -Value 'child' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot '.config\settings.json') -Value '{}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'script.ps1') -Value 'script' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'module.psm1') -Value 'module' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'tiny.bin') -Value 'x' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'old.txt') -Value 'old' -Encoding ASCII
        $largeStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'large.bin'))
        try {
            $largeStream.SetLength(11MB)
        }
        finally {
            $largeStream.Dispose()
        }
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item -LiteralPath (Join-Path $tempRoot 'old.txt')).LastAccessTime = (Get-Date).AddDays(-10)

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            $env:CLEANCLI_TEST_README = Join-Path $ProjectRoot 'README.md'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                $readmeText = Get-Content -LiteralPath $env:CLEANCLI_TEST_README -Raw
                $section = [regex]::Match($readmeText, '(?s)### Listing Filters and Qualifiers(?<body>.*?)## Key Bindings').Groups['body'].Value
                $codeSpanCommands = @([regex]::Matches($section, '`(ls[^`]*)`') | ForEach-Object { $_.Groups[1].Value })
                $fencedCommands = @($section -split "`r?`n" | Where-Object { $_ -match '^ls\s' })
                $commands = @($codeSpanCommands + $fencedCommands | ForEach-Object {
                    $_.Replace('\|', '|')
                } | Select-Object -Unique)

                Push-Location $env:CLEANCLI_TEST_PATH
                try {
                    Set-Alias -Name ls -Value Get-CleanCliChildItem -Scope Local -Force
                    foreach ($command in $commands) {
                        { Invoke-Expression $command | Out-Null } | Should Not Throw
                    }
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_README -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'sorts and slices directory listings with flags and qualifier strings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'a.txt') -Value 'a' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'b.txt') -Value ('b' * 20) -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'c.txt') -Value ('c' * 200) -Encoding ASCII
        (Get-Item -LiteralPath (Join-Path $tempRoot 'a.txt')).LastWriteTime = (Get-Date).AddMinutes(-30)
        (Get-Item -LiteralPath (Join-Path $tempRoot 'b.txt')).LastWriteTime = (Get-Date).AddMinutes(-20)
        (Get-Item -LiteralPath (Join-Path $tempRoot 'c.txt')).LastWriteTime = (Get-Date).AddMinutes(-10)

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Extension txt -Sort modified -Descending -First 2).Name -join ',' | Should Be 'c.txt,b.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -File -Extension txt -Sort name -Descending -Last 1).Name | Should Be 'a.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.OL[1,2]' -Extension txt).Name -join ',' | Should Be 'c.txt,b.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.on[2,3]').Name -join ',' | Should Be 'b.txt,c.txt'
                (Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.OL[1,3]' -Sort name -First 1).Name | Should Be 'a.txt'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'combines listing filters while preserving native icon item formatting' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'notes.txt') -Value 'notes' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null

                $item = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.m-1' -Extension md

                $item.Name | Should Be 'README.md'
                $item.PSObject.TypeNames[0] | Should Be 'CleanCli.IconItem'
                $item.DisplayName | Should Match 'README.md'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'throws clear errors for malformed or unsupported listing qualifiers' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                { Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '%' } | Should Throw "Unsupported ls qualifier '%'"
                { Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.m-' } | Should Throw "must include a number"
                { Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Qualifier '.on[1,2' } | Should Throw "missing ']'"
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves zsh-style listing qualifiers through the ls alias in a fresh shell' {
        $powerShellPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $powerShellPath) {
            Set-ItResult -Skipped -Because 'pwsh is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'fresh.txt') -Value 'fresh' -Encoding ASCII
        $configPath = Join-Path $env:TEMP "CleanCli.$([guid]::NewGuid().ToString('N')).config.psd1"
        Set-Content -LiteralPath $configPath -Value "@{ IconMode = 'native'; DirectoryReadAheadMode = 'disabled' }" -Encoding ASCII

        try {
            $command = @"
`$env:CLEANCLI_CONFIG_PATH = '$($configPath.Replace("'", "''"))'
Import-Module '$($ModulePath.Replace("'", "''"))' -Force
Enable-CleanCli
Set-Location '$($tempRoot.Replace("'", "''"))'
(ls -Qualifier '.m-7' | Select-Object -ExpandProperty Name) -join ','
"@

            $output = & $powerShellPath -NoProfile -Command $command

            ($output | Select-Object -Last 1) | Should Be 'fresh.txt'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves recursive listing filters through the ls alias in a fresh shell' {
        $powerShellPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $powerShellPath) {
            Set-ItResult -Skipped -Because 'pwsh is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tmp-root') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'test\tmp') | Out-Null
        $rootStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'tmp-root\root.log'))
        $nestedStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'test\tmp\nested.log'))
        try {
            $rootStream.SetLength(101KB)
            $nestedStream.SetLength(101KB)
        }
        finally {
            $rootStream.Dispose()
            $nestedStream.Dispose()
        }
        $configPath = Join-Path $env:TEMP "CleanCli.$([guid]::NewGuid().ToString('N')).config.psd1"
        Set-Content -LiteralPath $configPath -Value "@{ IconMode = 'native'; DirectoryReadAheadMode = 'disabled' }" -Encoding ASCII

        try {
            $command = @"
`$env:CLEANCLI_CONFIG_PATH = '$($configPath.Replace("'", "''"))'
Import-Module '$($ModulePath.Replace("'", "''"))' -Force
Enable-CleanCli
Set-Location '$($tempRoot.Replace("'", "''"))'
(ls -r '*/tmp*' '.L+100k*.log' | Sort-Object Name | Select-Object -ExpandProperty Name) -join ','
"@

            $output = & $powerShellPath -NoProfile -Command $command

            ($output | Select-Object -Last 1) | Should Be 'nested.log,root.log'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves PowerShell-style wildcard arguments through the ls alias in a fresh shell' {
        $powerShellPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $powerShellPath) {
            Set-ItResult -Skipped -Because 'pwsh is not available in this host.'
            return
        }

        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'folder.exe') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'app.exe') -Value 'app' -Encoding ASCII
        $configPath = Join-Path $env:TEMP "CleanCli.$([guid]::NewGuid().ToString('N')).config.psd1"
        Set-Content -LiteralPath $configPath -Value "@{ IconMode = 'native'; DirectoryReadAheadMode = 'disabled' }" -Encoding ASCII

        try {
            $command = @"
`$env:CLEANCLI_CONFIG_PATH = '$($configPath.Replace("'", "''"))'
Import-Module '$($ModulePath.Replace("'", "''"))' -Force
Enable-CleanCli
Set-Location '$($tempRoot.Replace("'", "''"))'
(ls *.exe | Select-Object -ExpandProperty Name) -join ','
"@

            $output = & $powerShellPath -NoProfile -Command $command

            ($output | Select-Object -Last 1) | Should Be 'app.exe'
        }
        finally {
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'uses supported native glyphs for common special directories' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        foreach ($name in @('.cache', '.config', '.docker', '.vscode', 'Contacts', 'Desktop', 'Documents', 'Downloads', 'Music')) {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot $name) | Out-Null
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Force
                $expected = @{
                    '.cache' = 'U+F013'
                    '.config' = 'U+E615'
                    '.docker' = 'U+E7B0'
                    '.vscode' = 'U+E70C'
                    'Contacts' = 'U+F0C0'
                    'Desktop' = 'U+F108'
                    'Documents' = 'U+F15C'
                    'Downloads' = 'U+F019'
                    'Music' = 'U+F001'
                }

                foreach ($name in $expected.Keys) {
                    $icon = ($items | Where-Object Name -eq $name).Icon
                    $codePoint = 'U+' + ([int][char]$icon[0]).ToString('X4')
                    $codePoint | Should Be $expected[$name]
                    Test-CleanCliIconGlyphSupported -Icon $icon | Should Be $true
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'rejects known legacy Nerd Font glyphs that render as invalid icons' {
        InModuleScope CleanCli {
            Test-CleanCliIconGlyphSupported -Icon ([string][char]0xf5e7) | Should Be $false
            Test-CleanCliIconGlyphSupported -Icon ([string][char]0xfbc9) | Should Be $false
            Test-CleanCliIconGlyphSupported -Icon ([string][char]0xfcbe) | Should Be $false
            Test-CleanCliIconGlyphSupported -Icon ([string][char]0xf832) | Should Be $false
            Test-CleanCliIconGlyphSupported -Icon ([string][char]0xf07b) | Should Be $true
        }
    }

    It 'uses native icons instead of importing Terminal-Icons when Nerd Font support is detected' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot '.cache') | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            $env:CLEANCLI_NERD_FONT = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value terminal-icons | Out-Null
                function script:Format-TerminalIcons {
                    throw 'Terminal-Icons should not be imported when native Nerd Font icons are available'
                }

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH -Force

                ($items | Where-Object Name -eq '.cache').Icon | Should Be ([string][char]0xf013)
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_NERD_FONT -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'reports icon routing diagnostics for the current shell' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_NERD_FONT = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value terminal-icons | Out-Null
            }

            $diagnostics = Get-CleanCliIconDiagnostics

            $diagnostics.ConfiguredIconMode | Should Be 'terminal-icons'
            $diagnostics.EffectiveIconMode | Should Be 'native'
            $diagnostics.NerdFontDetected | Should Be $true
            $diagnostics.LsDefinition | Should Not Be $null
            $diagnostics.DirDefinition | Should Not Be $null
            $diagnostics.TerminalIconsLoaded | Should Be $false
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_NERD_FONT -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'routes ls and dir through CleanCli when icon mode is enabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $originalLs = (Get-Alias ls -ErrorAction SilentlyContinue).Definition
        $originalDir = (Get-Alias dir -ErrorAction SilentlyContinue).Definition

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliIconAliases
            }

            (Get-Alias ls -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
            (Get-Alias dir -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
        }
        finally {
            InModuleScope CleanCli {
                Restore-CleanCliIconAliases
            }
            if ($originalLs) {
                Set-Alias -Name ls -Value $originalLs -Scope Global -Force
            }
            if ($originalDir) {
                Set-Alias -Name dir -Value $originalDir -Scope Global -Option AllScope -Force
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'routes ls and dir through CleanCli when icon mode is disabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $originalLs = (Get-Alias ls -ErrorAction SilentlyContinue).Definition
        $originalDir = (Get-Alias dir -ErrorAction SilentlyContinue).Definition

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null
                Set-CleanCliIconAliases
            }

            (Get-Alias ls -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
            (Get-Alias dir -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
        }
        finally {
            InModuleScope CleanCli {
                Restore-CleanCliIconAliases
            }
            if ($originalLs) {
                Set-Alias -Name ls -Value $originalLs -Scope Global -Force
            }
            if ($originalDir) {
                Set-Alias -Name dir -Value $originalDir -Scope Global -Option AllScope -Force
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'updates icon aliases when IconMode changes in an enabled session' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $originalLs = (Get-Alias ls -ErrorAction SilentlyContinue).Definition
        $originalDir = (Get-Alias dir -ErrorAction SilentlyContinue).Definition

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
            }

            (Get-Alias ls -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
            (Get-Alias dir -Scope Global).Definition | Should Be 'Get-CleanCliChildItem'
        }
        finally {
            InModuleScope CleanCli {
                Restore-CleanCliIconAliases
            }
            if ($originalLs) {
                Set-Alias -Name ls -Value $originalLs -Scope Global -Force
            }
            if ($originalDir) {
                Set-Alias -Name dir -Value $originalDir -Scope Global -Option AllScope -Force
            }
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders ASCII-safe icons for directory listings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'src') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value ascii | Out-Null

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH |
                    Where-Object { $_.Name -in @('src', 'README.md') }

                ($items | Where-Object Name -eq 'src').Icon | Should Be '[D]'
                ($items | Where-Object Name -eq 'README.md').Icon | Should Be '[F]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders fresh git repository branch metadata for native directory listings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'plain') | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'directory metadata should not invoke git.exe'
                }

                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH

                $repoItem = $items | Where-Object Name -eq 'repo'
                $plainItem = $items | Where-Object Name -eq 'plain'

                $repoItem.IsGitRepository | Should Be $true
                $repoItem.GitBranch | Should Be 'main'
                $repoItem.DisplayName | Should Match 'repo \[main\]'
                $plainItem.IsGitRepository | Should Be $false
                $plainItem.DisplayName | Should Not Match '\[main\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders ASCII-safe git repository markers for directory listings' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/ascii-branch' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value ascii | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null

                $repoItem = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $repoItem.Icon | Should Be '[G]'
                $repoItem.GitBranch | Should Be 'ascii-branch'
                $repoItem.DisplayName | Should Match '\[G\]\s+repo \[ascii-branch\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves worktree git files for directory metadata without invoking git status' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $worktree = Join-Path $tempRoot 'worktree'
        $gitDir = Join-Path $tempRoot '.git\worktrees\worktree'
        New-Item -ItemType Directory -Path $worktree | Out-Null
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $worktree '.git') -Value 'gitdir: ..\.git\worktrees\worktree' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/worktree-branch' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'directory metadata should not invoke git.exe'
                }

                $item = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'worktree'

                $item.IsGitRepository | Should Be $true
                $item.GitBranch | Should Be 'worktree-branch'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders detached HEAD metadata using the short hash' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value '1234567890abcdef' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null

                $item = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $item.GitBranch | Should Be '1234567'
                $item.DisplayName | Should Match 'repo \[1234567\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'drops stale repository metadata when .git is removed' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null
                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                Remove-Item -LiteralPath (Join-Path $env:CLEANCLI_TEST_PATH 'repo\.git') -Recurse -Force

                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $first.GitBranch | Should Be 'main'
                $second.IsGitRepository | Should Be $false
                $second.DisplayName | Should Not Match '\[main\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'refreshes expired branch metadata during directory listings by default' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null
                Set-CleanCliOption -Name DirectoryMetadataCacheMilliseconds -Value 1 | Out-Null
                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                Start-Sleep -Milliseconds 20

                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $first.GitBranch | Should Be 'main'
                $second.GitBranch | Should Be 'main'
                $second.DisplayName | Should Match '\[main\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'can opt out of inline git branch refresh for expired directory metadata' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null
                Set-CleanCliOption -Name DirectoryMetadataCacheMilliseconds -Value 1 | Out-Null
                Set-CleanCliOption -Name DirectoryAlwaysShowGitBranches -Value $false | Out-Null
                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                Start-Sleep -Milliseconds 20

                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $first.GitBranch | Should Be 'main'
                $second.GitBranch | Should Be ''
                $second.DisplayName | Should Not Match '\[main\]'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'invalidates changed HEAD metadata and refreshes through read-ahead' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryGitStatusMode -Value async | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 0 | Out-Null
                $script:CleanCliDirectoryMetadataCache = @{}
                $script:CleanCliDirectoryReadAheadJobs = @{}
                $script:CleanCliDirectoryReadAheadPending = @{}
                $script:CleanCliDirectoryReadAheadLastRequest = @{}
                $script:CleanCliDirectoryReadAheadCommand = {
                    param($Path, $Depth)
                    Get-CleanCliDirectoryMetadataInline -Path (Join-Path $Path 'repo') -DataSource 'read-ahead'
                }
                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                Start-Sleep -Milliseconds 20
                Set-Content -LiteralPath (Join-Path $env:CLEANCLI_TEST_PATH 'repo\.git\HEAD') -Value 'ref: refs/heads/feature' -Encoding ASCII

                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                $third = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $first.GitBranch | Should Be 'main'
                $second.GitBranch | Should Be 'feature'
                $third.GitBranch | Should Be 'feature'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'renders async git status colors and counts for repository directories' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        foreach ($name in @('clean', 'pending', 'dirty')) {
            $gitDir = Join-Path (Join-Path $tempRoot $name) '.git'
            New-Item -ItemType Directory -Path $gitDir | Out-Null
            Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 0 | Out-Null
                $script:CleanCliDirectoryMetadataCache = @{}
                $script:CleanCliDirectoryReadAheadJobs = @{}
                $script:CleanCliDirectoryReadAheadPending = @{}
                $script:CleanCliDirectoryReadAheadLastRequest = @{}
                $script:CleanCliDirectoryReadAheadCommand = {
                    param($Path, $Depth)
                    foreach ($name in @('clean', 'pending', 'dirty')) {
                        $repoPath = Join-Path $Path $name
                        $gitDir = Join-Path $repoPath '.git'
                        $statusText = switch ($name) {
                            'clean' { "## main...origin/main" }
                            'pending' { "## main...origin/main [ahead 2]" }
                            'dirty' { "## main...origin/main`n M changed.txt`nA  added.txt`n D deleted.txt`n?? new.txt" }
                        }
                        New-CleanCliDirectoryMetadata `
                            -Path $repoPath `
                            -IsGitRepository $true `
                            -GitRoot $repoPath `
                            -GitDir $gitDir `
                            -HeadPath (Join-Path $gitDir 'HEAD') `
                            -IndexPath (Join-Path $gitDir 'index') `
                            -Branch 'main' `
                            -DataSource 'read-ahead' `
                            -GitStatus (New-CleanCliDirectoryGitStatus -StatusText $statusText -DurationMilliseconds 12 -DataSource 'status')
                    }
                }

                Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Out-Null
                $items = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH

                $clean = $items | Where-Object Name -eq 'clean'
                $pending = $items | Where-Object Name -eq 'pending'
                $dirty = $items | Where-Object Name -eq 'dirty'
                $escape = [char]27

                $clean.GitStatusState | Should Be 'clean'
                $clean.DisplayName | Should Match "$escape\[38;2;124;255;155m"
                $clean.DisplayName | Should Match 'clean \[main\]'
                $pending.GitStatusState | Should Be 'pending'
                $pending.GitAhead | Should Be 2
                $pending.DisplayName | Should Match "$escape\[38;2;255;209;102m"
                $pending.DisplayName | Should Match 'pending \[main ahead 2\]'
                $dirty.GitStatusState | Should Be 'dirty'
                $dirty.GitStatusSummary | Should Be '?1 +1 ~1 -1'
                $dirty.DisplayName | Should Match "$escape\[38;2;255;107;107m"
                $dirty.DisplayName | Should Match 'dirty \[main \?1 \+1 ~1 -1\]'
                $script:CleanCliState.LastDirectoryGitStatusCount | Should Be 3
                $script:CleanCliState.LastDirectoryGitStatusDurationMilliseconds | Should Be 36
                $script:CleanCliState.LastDirectoryGitStatusTimedOutCount | Should Be 0
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps repository listing status unknown when directory git status mode is disabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $tempRoot 'repo'
        $gitDir = Join-Path $repo '.git'
        New-Item -ItemType Directory -Path $gitDir | Out-Null
        Set-Content -LiteralPath (Join-Path $gitDir 'HEAD') -Value 'ref: refs/heads/main' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryGitStatusMode -Value disabled | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 0 | Out-Null

                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'
                Start-Sleep -Milliseconds 250
                Receive-CleanCliDirectoryReadAhead
                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'repo'

                $first.GitStatusState | Should Be 'unknown'
                $second.GitStatusState | Should Be 'unknown'
                $second.DisplayName | Should Match 'repo \[main\]'
                $second.DisplayName | Should Match "$([char]27)\[38;2;125;211;252m"
                $second.DisplayName | Should Not Match 'ahead|\?1|\+1|~1|-1'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'debounces repeated directory read-ahead from ls' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'repo') | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 10000 | Out-Null
                $script:CleanCliDirectoryMetadataCache = @{}
                $script:CleanCliDirectoryReadAheadJobs = @{}
                $script:CleanCliDirectoryReadAheadPending = @{}
                $script:CleanCliDirectoryReadAheadLastRequest = @{}
                $script:CleanCliDirectoryReadAheadCalls = 0
                $script:CleanCliDirectoryReadAheadCommand = {
                    param($Path, $Depth)
                    $script:CleanCliDirectoryReadAheadCalls++
                    @()
                }

                Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Out-Null
                Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Out-Null

                $script:CleanCliDirectoryReadAheadCalls | Should Be 1
                $script:CleanCliState.LastDirectoryReadAheadSkippedReason | Should Be 'debounced'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'debounces repeated directory read-ahead from cd' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $target = Join-Path $tempRoot 'target'
        New-Item -ItemType Directory -Path $target | Out-Null
        $historyPath = Join-Path $tempRoot 'history.json'

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_LOCATION_HISTORY_PATH = $historyPath
            $env:CLEANCLI_TEST_PATH = $target
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 10000 | Out-Null
                $script:CleanCliDirectoryMetadataCache = @{}
                $script:CleanCliDirectoryReadAheadJobs = @{}
                $script:CleanCliDirectoryReadAheadPending = @{}
                $script:CleanCliDirectoryReadAheadLastRequest = @{}
                $script:CleanCliDirectoryReadAheadCalls = 0
                $script:CleanCliDirectoryReadAheadCommand = {
                    param($Path, $Depth)
                    $script:CleanCliDirectoryReadAheadCalls++
                    @()
                }

                Push-Location $env:TEMP
                try {
                    Set-CleanCliLocation -Path $env:CLEANCLI_TEST_PATH
                    Set-CleanCliLocation -Path $env:CLEANCLI_TEST_PATH
                }
                finally {
                    Pop-Location
                }

                $script:CleanCliDirectoryReadAheadCalls | Should Be 1
                $script:CleanCliState.LastDirectoryReadAheadSkippedReason | Should Be 'debounced'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_LOCATION_HISTORY_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'queues unique read-ahead paths when concurrency is full' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $first = Join-Path $tempRoot 'first'
        $second = Join-Path $tempRoot 'second'
        New-Item -ItemType Directory -Path $first | Out-Null
        New-Item -ItemType Directory -Path $second | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_FIRST_PATH = $first
            $env:CLEANCLI_SECOND_PATH = $second
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadDebounceMilliseconds -Value 0 | Out-Null
                $script:CleanCliDirectoryReadAheadJobs = @{
                    ([System.IO.Path]::GetFullPath($env:CLEANCLI_FIRST_PATH)) = @{
                        Path = [System.IO.Path]::GetFullPath($env:CLEANCLI_FIRST_PATH)
                        Job = $null
                    }
                }
                $script:CleanCliDirectoryReadAheadPending = @{}
                $script:CleanCliDirectoryReadAheadLastRequest = @{}

                Start-CleanCliDirectoryReadAhead -Path $env:CLEANCLI_SECOND_PATH

                $script:CleanCliDirectoryReadAheadJobs.Count | Should Be 1
                $script:CleanCliDirectoryReadAheadPending.Count | Should Be 1
                $script:CleanCliState.LastDirectoryReadAheadSkippedReason | Should Be 'queued'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_FIRST_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_SECOND_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'skips read-ahead for oversized directories' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'one') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'two') | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMaxDirectories -Value 1 | Out-Null
                $script:CleanCliDirectoryReadAheadCommand = {
                    throw 'oversized directories should not start read-ahead'
                }

                Start-CleanCliDirectoryReadAhead -Path $env:CLEANCLI_TEST_PATH

                $script:CleanCliState.LastDirectoryReadAheadSkippedReason | Should Be 'too many directories'
                $script:CleanCliDirectoryReadAheadCommand = $null
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps directory listing contents fresh while using metadata cache' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                Set-CleanCliOption -Name DirectoryReadAheadMode -Value disabled | Out-Null

                $first = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH
                Set-Content -LiteralPath (Join-Path $env:CLEANCLI_TEST_PATH 'created.txt') -Value 'new' -Encoding ASCII
                $second = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH
                Remove-Item -LiteralPath (Join-Path $env:CLEANCLI_TEST_PATH 'created.txt') -Force
                $third = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH

                ($first | Where-Object Name -eq 'created.txt') | Should Be $null
                ($second | Where-Object Name -eq 'created.txt').Name | Should Be 'created.txt'
                ($third | Where-Object Name -eq 'created.txt') | Should Be $null
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'preserves normal Get-ChildItem output when icon mode is disabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'file.txt') -Value 'test' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_PATH = $tempRoot
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value disabled | Out-Null

                $item = Get-CleanCliChildItem -Path $env:CLEANCLI_TEST_PATH | Where-Object Name -eq 'file.txt'

                $item.PSObject.TypeNames[0] | Should Not Be 'CleanCli.IconItem'
                ($item.PSObject.Properties.Name -contains 'DisplayName') | Should Be $false
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'formats icon directory listings as a compact table' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'hosts') -Value '127.0.0.1 localhost' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $tempRoot 'small.log') -Value 'small' -Encoding ASCII
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'logs') | Out-Null
        $largeStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'large.log'))
        $recursiveStream = [System.IO.File]::OpenWrite((Join-Path $tempRoot 'logs\recursive.log'))
        try {
            $largeStream.SetLength(101KB)
            $recursiveStream.SetLength(101KB)
        }
        finally {
            $largeStream.Dispose()
            $recursiveStream.Dispose()
        }

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
            }

            $text = Get-CleanCliChildItem -Path $tempRoot | Out-String

            $text | Should Match 'Mode\s+LastWriteTime\s+Length\s+Name'
            $text | Should Match '-a---\s+\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}'
            $text | Should Match 'hosts'
            $text | Should Not Match 'DisplayName\s+:'
            $text | Should Not Match 'FullName\s+:'

            $filteredText = Get-CleanCliChildItem -Path $tempRoot -Qualifier '.L+100kOL*.log' | Out-String

            $filteredText | Should Match 'Mode\s+LastWriteTime\s+Length\s+Name'
            $filteredText | Should Match 'large\.log'
            $filteredText | Should Not Match 'small\.log'

            $recursiveText = Get-CleanCliChildItem -Path $tempRoot -Recurse -Qualifier '.L+100k*.log' | Out-String

            $recursiveText | Should Match ([regex]::Escape("Directory: $(Join-Path $tempRoot 'logs')"))
            $recursiveText | Should Match 'Mode\s+LastWriteTime\s+Length\s+Name'
            $recursiveText | Should Match 'recursive\.log'

            $recursiveItem = Get-CleanCliChildItem -Path $tempRoot -Recurse -Qualifier '.L+100k*.log' |
                Where-Object Name -eq 'recursive.log'
            $recursiveItem.PSObject.TypeNames[0] | Should Be 'CleanCli.IconItem.Recursive'
            $recursiveItem.PSObject.TypeNames[1] | Should Be 'CleanCli.IconItem'
            $recursiveItem.Name | Should Be 'recursive.log'
            $recursiveItem.FullName | Should Be (Join-Path $tempRoot 'logs\recursive.log')
            $recursiveItem.Directory | Should Be (Join-Path $tempRoot 'logs')
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'colors native icon display names with ANSI sequences' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') -Value '# test' -Encoding ASCII

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
            }

            $item = Get-CleanCliChildItem -Path $tempRoot | Where-Object Name -eq 'README.md'
            $escape = [char]27

            $item.DisplayName | Should Match "$escape\[38;2;"
            $item.DisplayName | Should Match "$escape\[0m$"
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'delegates directory listings to Terminal-Icons when compatibility mode is selected and installed' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_NERD_FONT = '0'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value terminal-icons | Out-Null
                function script:Format-TerminalIcons {
                    process {
                        [pscustomobject]@{
                            Delegated = $true
                            Name = $_.Name
                        }
                    }
                }

                $items = Get-CleanCliChildItem -Path $env:TEMP

                ($items | Select-Object -First 1).Delegated | Should Be $true
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_NERD_FONT -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'does not run directory listing code during prompt rendering when icon mode is enabled' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_ASCII = '1'
            $env:NO_COLOR = '1'
            InModuleScope CleanCli {
                Initialize-CleanCliOptions | Out-Null
                Set-CleanCliOption -Name IconMode -Value native | Out-Null
                $script:CleanCliGitCommand = {
                    throw 'prompt test should not invoke git outside a repository'
                }
                function script:Get-ChildItem {
                    throw 'prompt rendering should not list directory items'
                }
                Push-Location $env:TEMP
                try {
                    $promptText = Invoke-CleanCliPrompt

                    $promptText | Should Not Match '\[D\]|\[F\]'
                }
                finally {
                    Pop-Location
                }
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_ASCII -ErrorAction SilentlyContinue
            Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'loads a non-interactive profile when icon mode is configured' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        $configPath = Join-Path $tempRoot 'CleanCli.config.psd1'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        Set-Content -LiteralPath $configPath -Value "@{ IconMode = 'native' }" -Encoding ASCII

        try {
            $command = "`$env:CLEANCLI_CONFIG_PATH = '$configPath'; `$env:CLEANCLI_INTERACTIVE_ONLY = '0'; . '$ProfilePath'; 'loaded'"
            $output = @(pwsh -NoProfile -NonInteractive -Command $command)

            $LASTEXITCODE | Should Be 0
            ($output -contains 'loaded') | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
