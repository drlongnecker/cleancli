function Find-CleanCliGitRepository {
    param([string]$Path = (Get-Location).ProviderPath)

    if (-not $Path) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }

    $directory = if ($item.PSIsContainer) { $item } else { $item.Directory }
    while ($null -ne $directory) {
        if (Test-CleanCliBareGitDirectory -Path $directory.FullName) {
            return [pscustomobject]@{
                Root = $directory.FullName
                GitDir = $directory.FullName
                HeadPath = Join-Path $directory.FullName 'HEAD'
                IndexPath = Join-Path $directory.FullName 'index'
            }
        }

        $gitPath = Join-Path $directory.FullName '.git'
        if (Test-Path -LiteralPath $gitPath) {
            $gitItem = Get-Item -LiteralPath $gitPath -Force
            if ($gitItem.PSIsContainer) {
                return [pscustomobject]@{
                    Root = $directory.FullName
                    GitDir = $gitItem.FullName
                    HeadPath = Join-Path $gitItem.FullName 'HEAD'
                    IndexPath = Join-Path $gitItem.FullName 'index'
                }
            }

            $content = Get-Content -LiteralPath $gitPath -TotalCount 1 -ErrorAction SilentlyContinue
            if ($content -match '^gitdir:\s*(.+)$') {
                $resolvedGitDir = Resolve-CleanCliGitPath -BasePath $directory.FullName -GitPath $matches[1]
                if (Test-Path -LiteralPath $resolvedGitDir) {
                    return [pscustomobject]@{
                        Root = $directory.FullName
                        GitDir = $resolvedGitDir
                        HeadPath = Join-Path $resolvedGitDir 'HEAD'
                        IndexPath = Join-Path $resolvedGitDir 'index'
                    }
                }
            }
        }

        $directory = $directory.Parent
    }

    $null
}

function Test-CleanCliBareGitDirectory {
    param([string]$Path)

    $headPath = Join-Path $Path 'HEAD'
    $objectsPath = Join-Path $Path 'objects'
    $refsPath = Join-Path $Path 'refs'
    $configPath = Join-Path $Path 'config'
    if (-not (Test-Path -LiteralPath $headPath) -or -not (Test-Path -LiteralPath $objectsPath) -or -not (Test-Path -LiteralPath $refsPath) -or -not (Test-Path -LiteralPath $configPath)) {
        return $false
    }

    $config = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
    [bool]($config -match '(?m)^\s*bare\s*=\s*true\s*$')
}

function Resolve-CleanCliGitPath {
    param(
        [string]$BasePath,
        [string]$GitPath
    )

    $trimmed = $GitPath.Trim()
    if ([System.IO.Path]::IsPathRooted($trimmed)) {
        return [System.IO.Path]::GetFullPath($trimmed)
    }

    [System.IO.Path]::GetFullPath((Join-Path $BasePath $trimmed))
}

function Get-CleanCliHeadName {
    param([string]$HeadPath)

    $head = Get-Content -LiteralPath $HeadPath -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $head) {
        return ''
    }

    if ($head -match '^ref:\s+refs/heads/(.+)$') {
        return $matches[1]
    }

    if ($head.Length -ge 7) {
        return $head.Substring(0, 7)
    }

    $head
}

function Get-CleanCliGitCacheKey {
    param(
        [object]$Repository,
        [string]$Path
    )

    $headTicks = 0
    $indexTicks = 0
    if (Test-Path -LiteralPath $Repository.HeadPath) {
        $headTicks = (Get-Item -LiteralPath $Repository.HeadPath).LastWriteTimeUtc.Ticks
    }
    if (Test-Path -LiteralPath $Repository.IndexPath) {
        $indexTicks = (Get-Item -LiteralPath $Repository.IndexPath).LastWriteTimeUtc.Ticks
    }

    '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $Repository.Root, $Path, $headTicks, $indexTicks, $script:CleanCliOptions.GitUntrackedMode, $script:CleanCliOptions.GitIgnoreSubmodules, $script:CleanCliOptions.GitDivergenceMode
}

function Get-CleanCliGitStatusArguments {
    $arguments = @(
        '--no-optional-locks'
        '-c'
        'core.quotepath=false'
        '-c'
        'color.status=false'
        'status'
        '--porcelain=v1'
        "--untracked-files=$($script:CleanCliOptions.GitUntrackedMode)"
        "--ignore-submodules=$($script:CleanCliOptions.GitIgnoreSubmodules)"
    )

    if ($script:CleanCliOptions.GitDivergenceMode -eq 'local') {
        $arguments += '--branch'
    }

    $arguments
}

function Get-CleanCliGitLastSuccessfulKey {
    param([object]$Repository)

    '{0}|{1}|{2}' -f $Repository.Root, $script:CleanCliOptions.GitUntrackedMode, $script:CleanCliOptions.GitIgnoreSubmodules
}

function Set-CleanCliGitLastSuccessfulInfo {
    param(
        [object]$Repository,
        [object]$Info
    )

    $script:CleanCliGitLastSuccessful[(Get-CleanCliGitLastSuccessfulKey -Repository $Repository)] = $Info
}

function Copy-CleanCliGitInfoForFallback {
    param(
        [object]$Repository,
        [object]$Info,
        [string]$Branch,
        [bool]$GitInvoked,
        [bool]$TimedOut,
        [bool]$GitSuppressed
    )

    if (-not $Info) {
        return $null
    }

    [pscustomobject]@{
        IsRepository = $true
        Root = $Repository.Root
        GitDir = $Repository.GitDir
        Branch = $Branch
        Dirty = $Info.Dirty
        Ahead = $Info.Ahead
        Behind = $Info.Behind
        Working = $Info.Working
        Staged = $Info.Staged
        Untracked = $Info.Untracked
        GitInvoked = $GitInvoked
        TimedOut = $TimedOut
        GitSuppressed = $GitSuppressed
        DataSource = 'last-successful'
        CacheKey = $Info.CacheKey
        GitArguments = $Info.GitArguments
        SuppressionCount = Get-CleanCliGitSuppressionCount -Repository $Repository
        SuppressionThreshold = $script:CleanCliOptions.GitSlowSuppressionTimeouts
    }
}

function Copy-CleanCliGitInfoWithDataSource {
    param(
        [object]$Info,
        [string]$DataSource
    )

    if (-not $Info) {
        return $null
    }

    [pscustomobject]@{
        IsRepository = $Info.IsRepository
        Root = $Info.Root
        GitDir = $Info.GitDir
        Branch = $Info.Branch
        Dirty = $Info.Dirty
        Ahead = $Info.Ahead
        Behind = $Info.Behind
        Working = $Info.Working
        Staged = $Info.Staged
        Untracked = $Info.Untracked
        GitInvoked = $false
        TimedOut = $false
        GitSuppressed = $false
        DataSource = $DataSource
        CacheKey = $Info.CacheKey
        GitArguments = $Info.GitArguments
        SuppressionCount = $Info.SuppressionCount
        SuppressionThreshold = $Info.SuppressionThreshold
    }
}

function New-CleanCliGitInfoFromStatusText {
    param(
        [object]$Repository,
        [string]$Branch,
        [string]$CacheKey,
        [string[]]$Arguments,
        [string]$StatusText
    )

    $status = Convert-CleanCliGitStatus -StatusText $StatusText
    $info = [ordered]@{
        IsRepository = $true
        Root = $Repository.Root
        GitDir = $Repository.GitDir
        Branch = $Branch
        Dirty = $status.Dirty
        Ahead = $status.Ahead
        Behind = $status.Behind
        Working = $status.Working
        Staged = $status.Staged
        Untracked = $status.Untracked
        GitInvoked = $true
        TimedOut = $false
        GitSuppressed = $false
    }
    Add-CleanCliGitDiagnostics -Info $info -Repository $Repository -CacheKey $CacheKey -Arguments $Arguments -DataSource 'full'

    [pscustomobject]$info
}

function Complete-CleanCliGitAsyncRefresh {
    param(
        [object]$Repository,
        [string]$Branch,
        [string]$CacheKey,
        [string[]]$Arguments,
        [string]$StatusText
    )

    if ($null -eq $StatusText) {
        Register-CleanCliGitTimeout -Repository $Repository
        return
    }

    Clear-CleanCliGitTimeout -Repository $Repository
    $info = New-CleanCliGitInfoFromStatusText -Repository $Repository -Branch $Branch -CacheKey $CacheKey -Arguments $Arguments -StatusText $StatusText
    $script:CleanCliGitCache[$CacheKey] = @{
        At = Get-Date
        Info = $info
    }
    Set-CleanCliGitLastSuccessfulInfo -Repository $Repository -Info $info
}

function Receive-CleanCliGitAsyncRefresh {
    param(
        [object]$Repository,
        [string]$Branch,
        [string]$CacheKey,
        [string[]]$Arguments
    )

    if (-not $script:CleanCliGitAsyncRefreshes.ContainsKey($CacheKey)) {
        return
    }

    $refresh = $script:CleanCliGitAsyncRefreshes[$CacheKey]
    if ($refresh.ContainsKey('StatusText')) {
        Complete-CleanCliGitAsyncRefresh -Repository $Repository -Branch $Branch -CacheKey $CacheKey -Arguments $Arguments -StatusText $refresh.StatusText
        $script:CleanCliGitAsyncRefreshes.Remove($CacheKey)
        return
    }

    $job = $refresh.Job
    if (-not $job -or $job.State -notin @('Completed', 'Failed', 'Stopped')) {
        return
    }

    $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $script:CleanCliGitAsyncRefreshes.Remove($CacheKey)

    if ($job.State -ne 'Completed' -or $null -eq $result) {
        Register-CleanCliGitTimeout -Repository $Repository
        return
    }

    $statusText = if ($result -is [array]) { $result -join "`n" } else { [string]$result }
    Complete-CleanCliGitAsyncRefresh -Repository $Repository -Branch $Branch -CacheKey $CacheKey -Arguments $Arguments -StatusText $statusText
}

function Start-CleanCliGitAsyncRefresh {
    param(
        [object]$Repository,
        [string]$CacheKey,
        [string[]]$Arguments
    )

    if ($script:CleanCliGitAsyncRefreshes.ContainsKey($CacheKey)) {
        return
    }

    if ($script:CleanCliGitAsyncCommand) {
        $script:CleanCliGitAsyncRefreshes[$CacheKey] = @{
            StatusText = & $script:CleanCliGitAsyncCommand $Repository.Root $Arguments
        }
        return
    }

    $timeout = $script:CleanCliGitTimeoutMilliseconds
    $root = $Repository.Root
    $job = Start-Job -ScriptBlock {
        param($RepositoryRoot, $GitArguments, $TimeoutMilliseconds)

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.FileName = 'git.exe'
        foreach ($argument in $GitArguments) {
            [void]$process.StartInfo.ArgumentList.Add($argument)
        }
        $process.StartInfo.WorkingDirectory = $RepositoryRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        try {
            [void]$process.Start()
            if (-not $process.WaitForExit($TimeoutMilliseconds)) {
                try {
                    $process.Kill()
                }
                catch {
                }
                return $null
            }

            $output = $process.StandardOutput.ReadToEnd()
            if ($process.ExitCode -ne 0) {
                return $null
            }

            $output
        }
        finally {
            if ($null -ne $process) {
                $process.Dispose()
            }
        }
    } -ArgumentList $root, $Arguments, $timeout

    $script:CleanCliGitAsyncRefreshes[$CacheKey] = @{
        Job = $job
    }
}

function Get-CleanCliGitLastSuccessfulInfo {
    param(
        [object]$Repository,
        [string]$Branch,
        [bool]$GitInvoked,
        [bool]$TimedOut,
        [bool]$GitSuppressed
    )

    $key = Get-CleanCliGitLastSuccessfulKey -Repository $Repository
    if (-not $script:CleanCliGitLastSuccessful.ContainsKey($key)) {
        return $null
    }

    Copy-CleanCliGitInfoForFallback -Repository $Repository -Info $script:CleanCliGitLastSuccessful[$key] -Branch $Branch -GitInvoked $GitInvoked -TimedOut $TimedOut -GitSuppressed $GitSuppressed
}

function Test-CleanCliGitStatusSuppressed {
    param([object]$Repository)

    if (-not $script:CleanCliSlowGitRepositories.ContainsKey($Repository.Root)) {
        return $false
    }

    $script:CleanCliSlowGitRepositories[$Repository.Root] -ge $script:CleanCliOptions.GitSlowSuppressionTimeouts
}

function Register-CleanCliGitTimeout {
    param([object]$Repository)

    $count = 0
    if ($script:CleanCliSlowGitRepositories.ContainsKey($Repository.Root)) {
        $count = $script:CleanCliSlowGitRepositories[$Repository.Root]
    }

    $script:CleanCliSlowGitRepositories[$Repository.Root] = $count + 1
}

function Clear-CleanCliGitTimeout {
    param([object]$Repository)

    if ($script:CleanCliSlowGitRepositories.ContainsKey($Repository.Root)) {
        $script:CleanCliSlowGitRepositories.Remove($Repository.Root)
    }
}

function Get-CleanCliGitSuppressionCount {
    param([object]$Repository)

    if (-not $Repository -or -not $script:CleanCliSlowGitRepositories.ContainsKey($Repository.Root)) {
        return 0
    }

    [int]$script:CleanCliSlowGitRepositories[$Repository.Root]
}

function Add-CleanCliGitDiagnostics {
    param(
        [object]$Info,
        [object]$Repository,
        [string]$CacheKey,
        [string[]]$Arguments,
        [string]$DataSource
    )

    $Info['DataSource'] = $DataSource
    $Info['CacheKey'] = $CacheKey
    $Info['GitArguments'] = if ($Arguments) { $Arguments -join ' ' } else { '' }
    $Info['SuppressionCount'] = Get-CleanCliGitSuppressionCount -Repository $Repository
    $Info['SuppressionThreshold'] = $script:CleanCliOptions.GitSlowSuppressionTimeouts
}

function Invoke-CleanCliGit {
    param(
        [string]$RepositoryRoot,
        [string[]]$Arguments
    )

    $script:CleanCliState.LastGitProcessCount++
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:CleanCliGitCommand) {
        try {
            return & $script:CleanCliGitCommand $RepositoryRoot $Arguments
        }
        finally {
            $timer.Stop()
            $script:CleanCliState.LastGitDurationMilliseconds = $timer.Elapsed.TotalMilliseconds
        }
    }

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = 'git.exe'
    foreach ($argument in $Arguments) {
        [void]$process.StartInfo.ArgumentList.Add($argument)
    }
    $process.StartInfo.WorkingDirectory = $RepositoryRoot
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $false
    $process.StartInfo.RedirectStandardError = $false
    $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true

    try {
        [void]$process.Start()
        if (-not $process.WaitForExit($script:CleanCliGitTimeoutMilliseconds)) {
            try {
                $process.Kill()
            }
            catch {
            }
            $script:CleanCliState.LastSlowGit = [pscustomobject]@{
                RepositoryRoot = $RepositoryRoot
                Arguments = $Arguments -join ' '
                ElapsedMilliseconds = $timer.ElapsedMilliseconds
                TimedOut = $true
                At = [datetime]::Now
            }
            return $null
        }

        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            $script:CleanCliState.LastSlowGit = [pscustomobject]@{
                RepositoryRoot = $RepositoryRoot
                Arguments = $Arguments -join ' '
                ElapsedMilliseconds = $timer.ElapsedMilliseconds
                TimedOut = $false
                Error = $errorOutput.Trim()
                At = [datetime]::Now
            }
            return $null
        }

        $output
    }
    finally {
        $timer.Stop()
        $script:CleanCliState.LastGitDurationMilliseconds = $timer.Elapsed.TotalMilliseconds
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Convert-CleanCliGitStatus {
    param([string]$StatusText)

    $result = [ordered]@{
        Dirty = $false
        Ahead = 0
        Behind = 0
        Working = 0
        Staged = 0
        Untracked = 0
    }

    if (-not $StatusText) {
        return [pscustomobject]$result
    }

    foreach ($line in ($StatusText -split "`r?`n")) {
        if (-not $line) {
            continue
        }

        if ($line -match '^## .*ahead (\d+)') {
            $result.Ahead = [int]$matches[1]
        }
        if ($line -match '^## .*behind (\d+)') {
            $result.Behind = [int]$matches[1]
        }
        if ($line -match '^## .*ahead (\d+), behind (\d+)') {
            $result.Ahead = [int]$matches[1]
            $result.Behind = [int]$matches[2]
        }
        if ($line.StartsWith('##')) {
            continue
        }

        $result.Dirty = $true
        if ($line.StartsWith('??')) {
            $result.Untracked++
            continue
        }
        if ($line.Length -ge 1 -and $line[0] -ne ' ') {
            $result.Staged++
        }
        if ($line.Length -ge 2 -and $line[1] -ne ' ') {
            $result.Working++
        }
    }

    [pscustomobject]$result
}

function Get-CleanCliGitInfo {
    param(
        [string]$Path = (Get-Location).ProviderPath,
        [switch]$SkipStatus
    )

    if ($script:CleanCliOptions.Count -eq 0) {
        Initialize-CleanCliOptions | Out-Null
    }

    $script:CleanCliState.LastGitProcessCount = 0
    $repository = Find-CleanCliGitRepository -Path $Path
    if ($null -eq $repository) {
        $info = [pscustomobject]@{
            IsRepository = $false
            Root = $null
            GitDir = $null
            Branch = ''
            Dirty = $false
            Ahead = 0
            Behind = 0
            Working = 0
            Staged = 0
            Untracked = 0
            GitInvoked = $false
            TimedOut = $false
            GitSuppressed = $false
            DataSource = 'none'
            CacheKey = ''
            GitArguments = ''
            SuppressionCount = 0
            SuppressionThreshold = $script:CleanCliOptions.GitSlowSuppressionTimeouts
        }
        $script:CleanCliState.LastGit = $info
        return $info
    }

    $branch = Get-CleanCliHeadName -HeadPath $repository.HeadPath
    $cacheKey = Get-CleanCliGitCacheKey -Repository $repository -Path $Path
    $statusArguments = Get-CleanCliGitStatusArguments
    $info = [ordered]@{
        IsRepository = $true
        Root = $repository.Root
        GitDir = $repository.GitDir
        Branch = $branch
        Dirty = $false
        Ahead = 0
        Behind = 0
        Working = 0
        Staged = 0
        Untracked = 0
        GitInvoked = $false
        TimedOut = $false
        GitSuppressed = $false
    }
    Add-CleanCliGitDiagnostics -Info $info -Repository $repository -CacheKey $cacheKey -Arguments $statusArguments -DataSource 'branch-only'

    if (-not $SkipStatus) {
        if ($script:CleanCliOptions.GitStatusMode -eq 'branch') {
            $finalBranchOnly = [pscustomobject]$info
            $script:CleanCliState.LastGit = $finalBranchOnly
            return $finalBranchOnly
        }

        if (Test-CleanCliGitStatusSuppressed -Repository $repository) {
            $lastSuccessful = Get-CleanCliGitLastSuccessfulInfo -Repository $repository -Branch $branch -GitInvoked $false -TimedOut $false -GitSuppressed $true
            if ($lastSuccessful) {
                $script:CleanCliState.LastGit = $lastSuccessful
                return $lastSuccessful
            }

            $info.GitSuppressed = $true
            Add-CleanCliGitDiagnostics -Info $info -Repository $repository -CacheKey $cacheKey -Arguments $statusArguments -DataSource 'suppressed'
            $finalSuppressed = [pscustomobject]$info
            $script:CleanCliState.LastGit = $finalSuppressed
            return $finalSuppressed
        }

        $cached = $script:CleanCliGitCache[$cacheKey]
        if ($cached -and ((Get-Date) - $cached.At).TotalMilliseconds -lt $script:CleanCliGitCacheMilliseconds) {
            $cachedInfo = Copy-CleanCliGitInfoWithDataSource -Info $cached.Info -DataSource 'cached'
            $script:CleanCliState.LastGit = $cachedInfo
            return $cachedInfo
        }

        if ($script:CleanCliOptions.GitStatusMode -eq 'async') {
            Receive-CleanCliGitAsyncRefresh -Repository $repository -Branch $branch -CacheKey $cacheKey -Arguments $statusArguments
            $cached = $script:CleanCliGitCache[$cacheKey]
            if ($cached -and ((Get-Date) - $cached.At).TotalMilliseconds -lt $script:CleanCliGitCacheMilliseconds) {
                $cachedInfo = Copy-CleanCliGitInfoWithDataSource -Info $cached.Info -DataSource 'cached'
                $script:CleanCliState.LastGit = $cachedInfo
                return $cachedInfo
            }

            Start-CleanCliGitAsyncRefresh -Repository $repository -CacheKey $cacheKey -Arguments $statusArguments
            $finalBranchOnly = [pscustomobject]$info
            $script:CleanCliState.LastGit = $finalBranchOnly
            return $finalBranchOnly
        }

        $statusText = Invoke-CleanCliGit -RepositoryRoot $repository.Root -Arguments $statusArguments
        $info.GitInvoked = $true
        if ($null -eq $statusText) {
            $info.TimedOut = $true
            Register-CleanCliGitTimeout -Repository $repository
            $lastSuccessful = Get-CleanCliGitLastSuccessfulInfo -Repository $repository -Branch $branch -GitInvoked $true -TimedOut $true -GitSuppressed $false
            if ($lastSuccessful) {
                $script:CleanCliState.LastGit = $lastSuccessful
                return $lastSuccessful
            }
            Add-CleanCliGitDiagnostics -Info $info -Repository $repository -CacheKey $cacheKey -Arguments $statusArguments -DataSource 'branch-only'
        }
        else {
            Clear-CleanCliGitTimeout -Repository $repository
            $status = Convert-CleanCliGitStatus -StatusText $statusText
            $info.Dirty = $status.Dirty
            $info.Ahead = $status.Ahead
            $info.Behind = $status.Behind
            $info.Working = $status.Working
            $info.Staged = $status.Staged
            $info.Untracked = $status.Untracked
            Add-CleanCliGitDiagnostics -Info $info -Repository $repository -CacheKey $cacheKey -Arguments $statusArguments -DataSource 'full'
            Set-CleanCliGitLastSuccessfulInfo -Repository $repository -Info ([pscustomobject]$info)
        }

        $finalInfo = [pscustomobject]$info
        $script:CleanCliGitCache[$cacheKey] = @{
            At = Get-Date
            Info = $finalInfo
        }
        $script:CleanCliState.LastGit = $finalInfo
        return $finalInfo
    }

    $final = [pscustomobject]$info
    $script:CleanCliState.LastGit = $final
    $final
}
