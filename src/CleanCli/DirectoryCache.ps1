function Resolve-CleanCliDirectoryPath {
    param([string]$Path = '.')

    if (-not $Path) {
        $Path = '.'
    }

    # Already absolute (e.g. from Get-ChildItem .FullName) — skip Test-Path + Resolve-Path
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
    }

    [System.IO.Path]::GetFullPath($Path)
}

function Get-CleanCliDirectoryTicks {
    param([string]$Path)

    try {
        [System.IO.Directory]::GetLastWriteTimeUtc($Path).Ticks
    }
    catch {
        0
    }
}

function Get-CleanCliFileTicks {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        return 0
    }

    $item.LastWriteTimeUtc.Ticks
}

function New-CleanCliDirectoryMetadata {
    param(
        [string]$Path,
        [bool]$IsGitRepository,
        [string]$GitRoot = '',
        [string]$GitDir = '',
        [string]$HeadPath = '',
        [string]$IndexPath = '',
        [string]$Branch = '',
        [string]$DataSource = 'none',
        [object]$GitStatus = $null
    )

    $status = if ($GitStatus) { $GitStatus } else { [pscustomobject]@{
        State = 'unknown'
        Ahead = 0
        Behind = 0
        Added = 0
        Modified = 0
        Deleted = 0
        Moved = 0
        Unmerged = 0
        Untracked = 0
        StatusSummary = ''
        DurationMilliseconds = 0
        TimedOut = $false
        DataSource = 'none'
        ScannedAtUtc = $null
    } }

    [pscustomobject]@{
        Path = $Path
        IsGitRepository = $IsGitRepository
        GitRoot = $GitRoot
        GitDir = $GitDir
        HeadPath = $HeadPath
        IndexPath = $IndexPath
        Branch = $Branch
        HeadLastWriteTicks = if ($HeadPath) { Get-CleanCliFileTicks -Path $HeadPath } else { 0 }
        IndexLastWriteTicks = if ($IndexPath) { Get-CleanCliFileTicks -Path $IndexPath } else { 0 }
        DirectoryLastWriteTicks = Get-CleanCliDirectoryTicks -Path $Path
        ScannedAtUtc = [datetime]::UtcNow
        DataSource = $DataSource
        StatusState = $status.State
        Ahead = $status.Ahead
        Behind = $status.Behind
        Added = $status.Added
        Modified = $status.Modified
        Deleted = $status.Deleted
        Moved = $status.Moved
        Unmerged = $status.Unmerged
        Untracked = $status.Untracked
        StatusSummary = $status.StatusSummary
        GitStatusDurationMilliseconds = $status.DurationMilliseconds
        GitStatusTimedOut = $status.TimedOut
        GitStatusDataSource = $status.DataSource
        GitStatusScannedAtUtc = $status.ScannedAtUtc
    }
}

function Find-CleanCliDirectoryGitRepository {
    param([string]$Path)

    # Check .git first — bare repos are rare; this skips one Test-Path per normal directory
    $gitPath = Join-Path $Path '.git'
    if (-not (Test-Path -LiteralPath $gitPath)) {
        # Not a standard repo — check for bare git (uncommon)
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            return $null
        }
        if (-not (Test-CleanCliBareGitDirectory -Path $Path)) {
            return $null
        }
        return [pscustomobject]@{
            Root = $Path
            GitDir = $Path
            HeadPath = Join-Path $Path 'HEAD'
            IndexPath = Join-Path $Path 'index'
        }
    }

    $gitItem = Get-Item -LiteralPath $gitPath -Force -ErrorAction SilentlyContinue
    if (-not $gitItem) {
        return $null
    }

    if ($gitItem.PSIsContainer) {
        return [pscustomobject]@{
            Root = $Path
            GitDir = $gitItem.FullName
            HeadPath = Join-Path $gitItem.FullName 'HEAD'
            IndexPath = Join-Path $gitItem.FullName 'index'
        }
    }

    $content = Get-Content -LiteralPath $gitPath -TotalCount 1 -ErrorAction SilentlyContinue
    if ($content -match '^gitdir:\s*(.+)$') {
        $resolvedGitDir = Resolve-CleanCliGitPath -BasePath $Path -GitPath $matches[1]
        if (Test-Path -LiteralPath $resolvedGitDir -PathType Container) {
            return [pscustomobject]@{
                Root = $Path
                GitDir = $resolvedGitDir
                HeadPath = Join-Path $resolvedGitDir 'HEAD'
                IndexPath = Join-Path $resolvedGitDir 'index'
            }
        }
    }

    $null
}

function Get-CleanCliDirectoryMetadataInline {
    param(
        [string]$Path,
        [string]$DataSource = 'inline'
    )

    $fullPath = Resolve-CleanCliDirectoryPath -Path $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        return $null
    }

    $repository = Find-CleanCliDirectoryGitRepository -Path $fullPath
    if (-not $repository) {
        return New-CleanCliDirectoryMetadata -Path $fullPath -IsGitRepository $false -DataSource $DataSource
    }

    New-CleanCliDirectoryMetadata `
        -Path $fullPath `
        -IsGitRepository $true `
        -GitRoot $repository.Root `
        -GitDir $repository.GitDir `
        -HeadPath $repository.HeadPath `
        -IndexPath $repository.IndexPath `
        -Branch (Get-CleanCliHeadName -HeadPath $repository.HeadPath) `
        -DataSource $DataSource
}

function New-CleanCliDirectoryGitStatus {
    param(
        [string]$StatusText = '',
        [double]$DurationMilliseconds = 0,
        [bool]$TimedOut = $false,
        [string]$DataSource = 'none'
    )

    if ($TimedOut) {
        return [pscustomobject]@{
            State = 'unknown'
            Ahead = 0
            Behind = 0
            Added = 0
            Modified = 0
            Deleted = 0
            Moved = 0
            Unmerged = 0
            Untracked = 0
            StatusSummary = ''
            DurationMilliseconds = $DurationMilliseconds
            TimedOut = $true
            DataSource = $DataSource
            ScannedAtUtc = [datetime]::UtcNow
        }
    }

    $parsed = Convert-CleanCliGitStatus -StatusText $StatusText
    $state = if ($parsed.Dirty) {
        'dirty'
    }
    elseif ($parsed.Ahead -gt 0) {
        'pending'
    }
    else {
        'clean'
    }

    [pscustomobject]@{
        State = $state
        Ahead = $parsed.Ahead
        Behind = $parsed.Behind
        Added = $parsed.Added
        Modified = $parsed.Modified
        Deleted = $parsed.Deleted
        Moved = $parsed.Moved
        Unmerged = $parsed.Unmerged
        Untracked = $parsed.Untracked
        StatusSummary = $parsed.StatusSummary
        DurationMilliseconds = $DurationMilliseconds
        TimedOut = $false
        DataSource = $DataSource
        ScannedAtUtc = [datetime]::UtcNow
    }
}

function Test-CleanCliDirectoryMetadataFresh {
    param([object]$Metadata)

    if (-not $Metadata -or -not $Metadata.Path) {
        return $false
    }

    # Check TTL first — if expired, skip all filesystem I/O
    if ((([datetime]::UtcNow) - ([datetime]$Metadata.ScannedAtUtc)).TotalMilliseconds -ge $script:CleanCliOptions.DirectoryMetadataCacheMilliseconds) {
        return $false
    }

    # Directory tick check also handles deletion (missing dir returns 0 ticks which won't match)
    if ((Get-CleanCliDirectoryTicks -Path $Metadata.Path) -ne [int64]$Metadata.DirectoryLastWriteTicks) {
        return $false
    }

    if ($Metadata.IsGitRepository) {
        if (-not $Metadata.HeadPath -or -not (Test-Path -LiteralPath $Metadata.HeadPath)) {
            return $false
        }

        if ((Get-CleanCliFileTicks -Path $Metadata.HeadPath) -ne [int64]$Metadata.HeadLastWriteTicks) {
            return $false
        }

        $indexPath = Get-CleanCliObjectValue -Object $Metadata -Name IndexPath -DefaultValue ''
        if ($indexPath -and (Get-CleanCliFileTicks -Path $indexPath) -ne [int64](Get-CleanCliObjectValue -Object $Metadata -Name IndexLastWriteTicks)) {
            return $false
        }
    }

    $true
}

function Set-CleanCliDirectoryMetadataCache {
    param([object]$Metadata)

    if (-not $Metadata -or -not $Metadata.Path) {
        return
    }

    $script:CleanCliDirectoryMetadataCache[$Metadata.Path] = $Metadata
}

function Get-CleanCliDirectoryMetadataForPath {
    param([string]$Path)

    if ($script:CleanCliOptions.Count -eq 0) {
        Initialize-CleanCliOptions | Out-Null
    }

    $fullPath = Resolve-CleanCliDirectoryPath -Path $Path
    $cached = $script:CleanCliDirectoryMetadataCache[$fullPath]
    if ($cached -and (Test-CleanCliDirectoryMetadataFresh -Metadata $cached)) {
        return $cached
    }

    if ($cached) {
        $script:CleanCliDirectoryMetadataCache.Remove($fullPath)
        if (-not $script:CleanCliOptions.DirectoryAlwaysShowGitBranches) {
            return $null
        }
    }

    $metadata = Get-CleanCliDirectoryMetadataInline -Path $fullPath -DataSource inline
    Set-CleanCliDirectoryMetadataCache -Metadata $metadata
    $metadata
}

function Receive-CleanCliDirectoryReadAhead {
    $completedKeys = @()
    foreach ($key in @($script:CleanCliDirectoryReadAheadJobs.Keys)) {
        $entry = $script:CleanCliDirectoryReadAheadJobs[$key]
        $job = $entry.Job
        if (-not $job -or $job.State -notin @('Completed', 'Failed', 'Stopped')) {
            continue
        }

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        $timer.Stop()
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $completedKeys += $key

        $script:CleanCliState.LastDirectoryReadAheadPath = $entry.Path
        $script:CleanCliState.LastDirectoryReadAheadDurationMilliseconds = $timer.Elapsed.TotalMilliseconds
        if ($job.State -ne 'Completed') {
            $script:CleanCliState.LastDirectoryReadAheadSkippedReason = $job.State.ToLowerInvariant()
            continue
        }

        if ($script:CleanCliDirectoryReadAheadLastRequest.ContainsKey($entry.Path)) {
            $lastRequest = [datetime]$script:CleanCliDirectoryReadAheadLastRequest[$entry.Path]
            if ($entry.RequestedAtUtc -and ([datetime]$entry.RequestedAtUtc) -lt $lastRequest) {
                $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'superseded'
                continue
            }
        }

        $statusCount = 0
        $statusDuration = 0
        $timedOutCount = 0
        foreach ($metadata in @($result)) {
            if ($metadata -and $metadata.Path) {
                Set-CleanCliDirectoryMetadataCache -Metadata $metadata
                if ((Get-CleanCliObjectValue -Object $metadata -Name GitStatusDataSource -DefaultValue 'none') -ne 'none') {
                    $statusCount++
                    $statusDuration += [double](Get-CleanCliObjectValue -Object $metadata -Name GitStatusDurationMilliseconds)
                    if ([bool](Get-CleanCliObjectValue -Object $metadata -Name GitStatusTimedOut -DefaultValue $false)) {
                        $timedOutCount++
                    }
                }
            }
        }

        $script:CleanCliState.LastDirectoryGitStatusCount = $statusCount
        $script:CleanCliState.LastDirectoryGitStatusDurationMilliseconds = $statusDuration
        $script:CleanCliState.LastDirectoryGitStatusTimedOutCount = $timedOutCount
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = ''
    }

    foreach ($key in $completedKeys) {
        $script:CleanCliDirectoryReadAheadJobs.Remove($key)
    }

    Start-CleanCliDirectoryReadAheadPending
}

function Start-CleanCliDirectoryReadAheadPending {
    if ($script:CleanCliDirectoryReadAheadJobs.Count -ge $script:CleanCliDirectoryReadAheadMaxActive) {
        return
    }

    foreach ($key in @($script:CleanCliDirectoryReadAheadPending.Keys)) {
        if ($script:CleanCliDirectoryReadAheadJobs.Count -ge $script:CleanCliDirectoryReadAheadMaxActive) {
            return
        }

        $entry = $script:CleanCliDirectoryReadAheadPending[$key]
        $script:CleanCliDirectoryReadAheadPending.Remove($key)
        Start-CleanCliDirectoryReadAheadJob -Path $entry.Path -RequestId $entry.RequestId -RequestedAtUtc $entry.RequestedAtUtc
    }
}

function Start-CleanCliDirectoryReadAheadJob {
    param(
        [string]$Path,
        [string]$RequestId,
        [datetime]$RequestedAtUtc
    )

    if ($script:CleanCliDirectoryReadAheadCommand) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $items = & $script:CleanCliDirectoryReadAheadCommand $Path $script:CleanCliOptions.DirectoryReadAheadDepth
        $timer.Stop()
        $statusCount = 0
        $statusDuration = 0
        $timedOutCount = 0
        foreach ($metadata in @($items)) {
            Set-CleanCliDirectoryMetadataCache -Metadata $metadata
            if ($metadata -and (Get-CleanCliObjectValue -Object $metadata -Name GitStatusDataSource -DefaultValue 'none') -ne 'none') {
                $statusCount++
                $statusDuration += [double](Get-CleanCliObjectValue -Object $metadata -Name GitStatusDurationMilliseconds)
                if ([bool](Get-CleanCliObjectValue -Object $metadata -Name GitStatusTimedOut -DefaultValue $false)) {
                    $timedOutCount++
                }
            }
        }
        $script:CleanCliState.LastDirectoryReadAheadPath = $Path
        $script:CleanCliState.LastDirectoryReadAheadDurationMilliseconds = $timer.Elapsed.TotalMilliseconds
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = ''
        $script:CleanCliState.LastDirectoryGitStatusCount = $statusCount
        $script:CleanCliState.LastDirectoryGitStatusDurationMilliseconds = $statusDuration
        $script:CleanCliState.LastDirectoryGitStatusTimedOutCount = $timedOutCount
        return
    }

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'Start-ThreadJob unavailable'
        return
    }

    $depth = [int]$script:CleanCliOptions.DirectoryReadAheadDepth
    $maxDirectories = [int]$script:CleanCliOptions.DirectoryReadAheadMaxDirectories
    $gitStatusMode = $script:CleanCliOptions.DirectoryGitStatusMode
    $timeoutMilliseconds = [int]$script:CleanCliOptions.GitTimeoutMilliseconds
    $untrackedMode = $script:CleanCliOptions.GitUntrackedMode
    $ignoreSubmodules = $script:CleanCliOptions.GitIgnoreSubmodules
    $job = Start-ThreadJob -ScriptBlock {
        param($RootPath, $Depth, $MaxDirectories, $GitStatusMode, $TimeoutMilliseconds, $UntrackedMode, $IgnoreSubmodules)

        function Get-DirectoryTicks {
            param([string]$Path)
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            if (-not $item) { return 0 }
            $item.LastWriteTimeUtc.Ticks
        }

        function Get-FileTicks {
            param([string]$Path)
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            if (-not $item) { return 0 }
            $item.LastWriteTimeUtc.Ticks
        }

        function Resolve-GitPath {
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

        function Get-HeadName {
            param([string]$HeadPath)
            $head = Get-Content -LiteralPath $HeadPath -TotalCount 1 -ErrorAction SilentlyContinue
            if (-not $head) { return '' }
            if ($head -match '^ref:\s+refs/heads/(.+)$') { return $matches[1] }
            if ($head.Length -ge 7) { return $head.Substring(0, 7) }
            $head
        }

        function New-Metadata {
            param(
                [string]$Path,
                [bool]$IsGitRepository,
                [string]$GitDir = '',
                [string]$HeadPath = '',
                [string]$IndexPath = '',
                [string]$Branch = '',
                [object]$GitStatus = $null
            )
            $status = if ($GitStatus) { $GitStatus } else { [pscustomobject]@{
                State = 'unknown'
                Ahead = 0
                Behind = 0
                Added = 0
                Modified = 0
                Deleted = 0
                Moved = 0
                Unmerged = 0
                Untracked = 0
                StatusSummary = ''
                DurationMilliseconds = 0
                TimedOut = $false
                DataSource = 'none'
                ScannedAtUtc = $null
            } }
            [pscustomobject]@{
                Path = $Path
                IsGitRepository = $IsGitRepository
                GitRoot = if ($IsGitRepository) { $Path } else { '' }
                GitDir = $GitDir
                HeadPath = $HeadPath
                IndexPath = $IndexPath
                Branch = $Branch
                HeadLastWriteTicks = if ($HeadPath) { Get-FileTicks -Path $HeadPath } else { 0 }
                IndexLastWriteTicks = if ($IndexPath) { Get-FileTicks -Path $IndexPath } else { 0 }
                DirectoryLastWriteTicks = Get-DirectoryTicks -Path $Path
                ScannedAtUtc = [datetime]::UtcNow
                DataSource = 'read-ahead'
                StatusState = $status.State
                Ahead = $status.Ahead
                Behind = $status.Behind
                Added = $status.Added
                Modified = $status.Modified
                Deleted = $status.Deleted
                Moved = $status.Moved
                Unmerged = $status.Unmerged
                Untracked = $status.Untracked
                StatusSummary = $status.StatusSummary
                GitStatusDurationMilliseconds = $status.DurationMilliseconds
                GitStatusTimedOut = $status.TimedOut
                GitStatusDataSource = $status.DataSource
                GitStatusScannedAtUtc = $status.ScannedAtUtc
            }
        }

        function Format-StatusSummary {
            param([object]$Status)

            $parts = @()
            foreach ($entry in @(
                , @('Untracked', '?')
                , @('Added', '+')
                , @('Modified', '~')
                , @('Deleted', '-')
                , @('Moved', '>')
                , @('Unmerged', 'x')
            )) {
                $value = $Status.PSObject.Properties[$entry[0]].Value
                if ($value -gt 0) {
                    $parts += "$($entry[1])$value"
                }
            }

            $parts -join ' '
        }

        function Add-StatusCode {
            param(
                [object]$Status,
                [string]$Code
            )

            switch ($Code) {
                'A' { $Status.Added++ }
                'M' { $Status.Modified++ }
                'D' { $Status.Deleted++ }
                'R' { $Status.Moved++ }
                'C' { $Status.Moved++ }
                'U' { $Status.Unmerged++ }
            }
        }

        function Convert-StatusText {
            param([string]$StatusText)

            $status = [pscustomobject]@{
                Dirty = $false
                Ahead = 0
                Behind = 0
                Added = 0
                Modified = 0
                Deleted = 0
                Moved = 0
                Unmerged = 0
                Untracked = 0
                StatusSummary = ''
            }

            foreach ($line in ($StatusText -split "`r?`n")) {
                if (-not $line) { continue }
                if ($line -match '^## .*ahead (\d+)') { $status.Ahead = [int]$matches[1] }
                if ($line -match '^## .*behind (\d+)') { $status.Behind = [int]$matches[1] }
                if ($line -match '^## .*ahead (\d+), behind (\d+)') {
                    $status.Ahead = [int]$matches[1]
                    $status.Behind = [int]$matches[2]
                }
                if ($line.StartsWith('##')) { continue }

                $status.Dirty = $true
                if ($line.StartsWith('??')) {
                    $status.Untracked++
                    continue
                }

                if ($line.Length -ge 2) {
                    $combined = "$($line[0])$($line[1])"
                    if ($combined -in @('DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU')) {
                        $status.Unmerged++
                        continue
                    }

                    Add-StatusCode -Status $status -Code ([string]$line[0])
                    Add-StatusCode -Status $status -Code ([string]$line[1])
                }
            }

            $status.StatusSummary = Format-StatusSummary -Status $status
            $status
        }

        function New-GitStatus {
            param(
                [string]$StatusText = '',
                [double]$DurationMilliseconds = 0,
                [bool]$TimedOut = $false
            )

            if ($TimedOut) {
                return [pscustomobject]@{
                    State = 'unknown'
                    Ahead = 0
                    Behind = 0
                    Added = 0
                    Modified = 0
                    Deleted = 0
                    Moved = 0
                    Unmerged = 0
                    Untracked = 0
                    StatusSummary = ''
                    DurationMilliseconds = $DurationMilliseconds
                    TimedOut = $true
                    DataSource = 'status'
                    ScannedAtUtc = [datetime]::UtcNow
                }
            }

            $parsed = Convert-StatusText -StatusText $StatusText
            $state = if ($parsed.Dirty) { 'dirty' } elseif ($parsed.Ahead -gt 0) { 'pending' } else { 'clean' }
            [pscustomobject]@{
                State = $state
                Ahead = $parsed.Ahead
                Behind = $parsed.Behind
                Added = $parsed.Added
                Modified = $parsed.Modified
                Deleted = $parsed.Deleted
                Moved = $parsed.Moved
                Unmerged = $parsed.Unmerged
                Untracked = $parsed.Untracked
                StatusSummary = $parsed.StatusSummary
                DurationMilliseconds = $DurationMilliseconds
                TimedOut = $false
                DataSource = 'status'
                ScannedAtUtc = [datetime]::UtcNow
            }
        }

        function Invoke-GitStatus {
            param([string]$RepositoryRoot)

            if ($GitStatusMode -eq 'disabled') {
                return $null
            }

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo.FileName = 'git.exe'
            foreach ($argument in @(
                '--no-optional-locks',
                '-c',
                'core.quotepath=false',
                '-c',
                'color.status=false',
                'status',
                '--porcelain=v1',
                '--branch',
                "--untracked-files=$UntrackedMode",
                "--ignore-submodules=$IgnoreSubmodules"
            )) {
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
                    try { $process.Kill() } catch {}
                    $timer.Stop()
                    return New-GitStatus -DurationMilliseconds $timer.Elapsed.TotalMilliseconds -TimedOut $true
                }

                $output = $process.StandardOutput.ReadToEnd()
                $timer.Stop()
                if ($process.ExitCode -ne 0) {
                    return New-GitStatus -DurationMilliseconds $timer.Elapsed.TotalMilliseconds -TimedOut $true
                }

                New-GitStatus -StatusText $output -DurationMilliseconds $timer.Elapsed.TotalMilliseconds
            }
            finally {
                if ($null -ne $process) {
                    $process.Dispose()
                }
            }
        }

        function Test-BareGitDirectory {
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

        function Get-Metadata {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
            if (Test-BareGitDirectory -Path $Path) {
                $headPath = Join-Path $Path 'HEAD'
                return New-Metadata -Path $Path -IsGitRepository $true -GitDir $Path -HeadPath $headPath -IndexPath (Join-Path $Path 'index') -Branch (Get-HeadName -HeadPath $headPath) -GitStatus (Invoke-GitStatus -RepositoryRoot $Path)
            }

            $gitPath = Join-Path $Path '.git'
            if (-not (Test-Path -LiteralPath $gitPath)) {
                return New-Metadata -Path $Path -IsGitRepository $false
            }

            $gitItem = Get-Item -LiteralPath $gitPath -Force -ErrorAction SilentlyContinue
            if (-not $gitItem) {
                return New-Metadata -Path $Path -IsGitRepository $false
            }

            if ($gitItem.PSIsContainer) {
                $headPath = Join-Path $gitItem.FullName 'HEAD'
                return New-Metadata -Path $Path -IsGitRepository $true -GitDir $gitItem.FullName -HeadPath $headPath -IndexPath (Join-Path $gitItem.FullName 'index') -Branch (Get-HeadName -HeadPath $headPath) -GitStatus (Invoke-GitStatus -RepositoryRoot $Path)
            }

            $content = Get-Content -LiteralPath $gitPath -TotalCount 1 -ErrorAction SilentlyContinue
            if ($content -match '^gitdir:\s*(.+)$') {
                $gitDir = Resolve-GitPath -BasePath $Path -GitPath $matches[1]
                if (Test-Path -LiteralPath $gitDir -PathType Container) {
                    $headPath = Join-Path $gitDir 'HEAD'
                    return New-Metadata -Path $Path -IsGitRepository $true -GitDir $gitDir -HeadPath $headPath -IndexPath (Join-Path $gitDir 'index') -Branch (Get-HeadName -HeadPath $headPath) -GitStatus (Invoke-GitStatus -RepositoryRoot $Path)
                }
            }

            New-Metadata -Path $Path -IsGitRepository $false
        }

        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue([pscustomobject]@{ Path = $RootPath; Depth = 0 })
        $count = 0
        while ($queue.Count -gt 0 -and $count -lt $MaxDirectories) {
            $current = $queue.Dequeue()
            $children = @(Get-ChildItem -LiteralPath $current.Path -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                if ($count -ge $MaxDirectories) { break }
                $fullName = [System.IO.Path]::GetFullPath($child.FullName)
                Get-Metadata -Path $fullName
                $count++
                if ($current.Depth + 1 -lt $Depth) {
                    $queue.Enqueue([pscustomobject]@{ Path = $fullName; Depth = $current.Depth + 1 })
                }
            }
        }
    } -ArgumentList $Path, $depth, $maxDirectories, $gitStatusMode, $timeoutMilliseconds, $untrackedMode, $ignoreSubmodules

    $script:CleanCliDirectoryReadAheadJobs[$Path] = @{
        Path = $Path
        RequestId = $RequestId
        RequestedAtUtc = $RequestedAtUtc
        Job = $job
    }
}

function Start-CleanCliDirectoryReadAhead {
    param([string]$Path = (Get-Location).ProviderPath)

    if ($script:CleanCliOptions.Count -eq 0) {
        Initialize-CleanCliOptions | Out-Null
    }

    Receive-CleanCliDirectoryReadAhead

    if ($script:CleanCliOptions.DirectoryReadAheadMode -eq 'disabled') {
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'disabled'
        return
    }

    $fullPath = Resolve-CleanCliDirectoryPath -Path $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'missing directory'
        return
    }

    $now = [datetime]::UtcNow
    if ($script:CleanCliDirectoryReadAheadLastRequest.ContainsKey($fullPath)) {
        $last = [datetime]$script:CleanCliDirectoryReadAheadLastRequest[$fullPath]
        if (($now - $last).TotalMilliseconds -lt $script:CleanCliOptions.DirectoryReadAheadDebounceMilliseconds) {
            $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'debounced'
            return
        }
    }
    $script:CleanCliDirectoryReadAheadLastRequest[$fullPath] = $now

    if ($script:CleanCliDirectoryReadAheadJobs.ContainsKey($fullPath)) {
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'already active'
        return
    }

    $childDirectories = @(Get-ChildItem -LiteralPath $fullPath -Directory -Force -ErrorAction SilentlyContinue)
    if ($childDirectories.Count -gt $script:CleanCliOptions.DirectoryReadAheadMaxDirectories) {
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'too many directories'
        return
    }

    $requestId = [guid]::NewGuid().ToString('N')
    if ($script:CleanCliDirectoryReadAheadJobs.Count -ge $script:CleanCliDirectoryReadAheadMaxActive) {
        $script:CleanCliDirectoryReadAheadPending[$fullPath] = @{
            Path = $fullPath
            RequestId = $requestId
            RequestedAtUtc = $now
        }
        $script:CleanCliState.LastDirectoryReadAheadSkippedReason = 'queued'
        return
    }

    Start-CleanCliDirectoryReadAheadJob -Path $fullPath -RequestId $requestId -RequestedAtUtc $now
}
