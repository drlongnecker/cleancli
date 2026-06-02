$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ProjectRoot 'src\CleanCli\CleanCli.psd1'
$ProfilePath = Join-Path $ProjectRoot 'src\Microsoft.PowerShell_profile.ps1'

Describe 'CleanCli profile bootstrap' {
    It 'does not load online or slow prompt dependencies' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Not Match 'import-module\s+posh-git'
        $profileText | Should Not Match 'import-module\s+mklink'
        $profileText | Should Not Match 'oh-my-posh'
    }

    It 'loads Terminal-Icons from the local module path when available' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Match 'Import-Module Terminal-Icons -ErrorAction SilentlyContinue'
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
        ($commands -contains 'Get-CleanCliOption') | Should Be $true
        ($commands -contains 'Set-CleanCliOption') | Should Be $true
        ($commands -contains 'Get-CleanCliChildItem') | Should Be $true
        ($commands -contains 'Set-CleanCliLocation') | Should Be $true
        ($commands -contains 'Get-CleanCliLocationHistory') | Should Be $true
        ($commands -contains 'Open-CleanCliExplorer') | Should Be $true
        ($commands -contains 'Show-CleanCliGitLog') | Should Be $true
        ($commands -contains 'Install-CleanCli') | Should Be $true
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
            $options.PathDisplayMode | Should Be 'auto'
            $options.PromptLayout | Should Be 'single'
            $options.IconMode | Should Be 'disabled'
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
            $env:CLEANCLI_TEST_USER_CONFIG_PATH = Join-Path $configRoot 'CleanCli.config.psd1'
            $env:CLEANCLI_TEST_START_PATH = $startPath
            InModuleScope CleanCli {
                $script:CleanCliUserConfigPathOverride = $env:CLEANCLI_TEST_USER_CONFIG_PATH
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
            Remove-Item Env:\CLEANCLI_TEST_USER_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_START_PATH -ErrorAction SilentlyContinue
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
            $path = Join-Path $home 'AppData\Roaming\nocturnal-souls-launcher\blob_storage\09064e10-8a6c-4c30-972c-f8980ebcfe86'

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
            ($bindings | Where-Object { $_.Key -eq 'UpArrow' }).Function | Should Be 'HistorySearchBackward'
            ($bindings | Where-Object { $_.Key -eq 'DownArrow' }).Function | Should Be 'HistorySearchForward'
            ($bindings | Where-Object { $_.Key -eq 'RightArrow' }).Function | Should Be 'AcceptSuggestion'
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
                $folder.DisplayName | Should Match 'src$'
                $markdown.DisplayName | Should Match 'README.md$'
            }
        }
        finally {
            Remove-Item Env:\CLEANCLI_CONFIG_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:\CLEANCLI_TEST_PATH -ErrorAction SilentlyContinue
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

    It 'delegates directory listings to Terminal-Icons when compatibility mode is selected and installed' {
        $tempRoot = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        try {
            $env:CLEANCLI_CONFIG_PATH = Join-Path $tempRoot 'CleanCli.config.psd1'
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
