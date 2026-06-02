$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ProjectRoot 'src\CleanCli\CleanCli.psd1'
$ProfilePath = Join-Path $ProjectRoot 'src\Microsoft.PowerShell_profile.ps1'

Describe 'CleanCli profile bootstrap' {
    It 'does not load online or slow prompt dependencies' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Not Match 'import-module\s+posh-git'
        $profileText | Should Not Match 'import-module\s+-?name\s+terminal-icons'
        $profileText | Should Not Match 'import-module\s+mklink'
        $profileText | Should Not Match 'oh-my-posh'
    }

    It 'contains a CleanCli disable gate' {
        $profileText = Get-Content -LiteralPath $ProfilePath -Raw

        $profileText | Should Match 'CLEANCLI_DISABLE'
        $profileText | Should Match 'Enable-CleanCli'
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
    }

    It 'returns default CleanCli options' {
        $options = Get-CleanCliOption

        $options.GitTimeoutMilliseconds | Should Be 1000
        $options.GitCacheMilliseconds | Should Be 750
        $options.GitUntrackedMode | Should Be 'normal'
        $options.GitIgnoreSubmodules | Should Be 'none'
        $options.GitStatusMode | Should Be 'full'
        $options.GitDivergenceMode | Should Be 'none'
        $options.PathDisplayMode | Should Be 'auto'
        $options.PromptLayout | Should Be 'single'
        $options.AsciiMode | Should Be $false
        $options.TransientPrompt | Should Be $false
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
}
