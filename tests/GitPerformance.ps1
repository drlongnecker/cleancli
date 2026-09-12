<#
.SYNOPSIS
Benchmark harness for CleanCli Git operations
#>

param(
    [int]$Iterations = 50,
    [string]$TestRepo = (Get-Location).ProviderPath
)

$ErrorActionPreference = 'Stop'

function Measure-Operation {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock,
        [int]$Iterations = 50
    )
    $times = @()
    for ($i = 0; $i -lt $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $ScriptBlock
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
    }
    $times = $times | Sort-Object
    $p50 = $times[[math]::Floor($times.Count * 0.50)]
    $p95 = $times[[math]::Floor($times.Count * 0.95)]
    $p99 = $times[[math]::Floor($times.Count * 0.99)]
    $avg = ($times | Measure-Object -Average).Average
    [pscustomobject]@{
        Name = $Name
        Iterations = $Iterations
        AvgMs = [math]::Round($avg, 2)
        P50Ms = [math]::Round($p50, 2)
        P95Ms = [math]::Round($p95, 2)
        P99Ms = [math]::Round($p99, 2)
        MinMs = [math]::Round($times[0], 2)
        MaxMs = [math]::Round($times[-1], 2)
    }
}

function Invoke-ModuleScope {
    param([scriptblock]$ScriptBlock)
    & (Get-Module CleanCli) $ScriptBlock
}

# Import module
if (Get-Module CleanCli) { Remove-Module CleanCli -Force }
Import-Module (Join-Path $PSScriptRoot '..\src\CleanCli\CleanCli.psd1') -Force
Enable-CleanCli

# Ensure we're in a git repo
if (-not (Test-Path (Join-Path $TestRepo '.git'))) {
    Write-Error "Not a git repository: $TestRepo"
    exit 1
}

Set-Location $TestRepo

Write-Host "=== CleanCli Git Performance Benchmark ===" -ForegroundColor Cyan
Write-Host "Repo: $TestRepo" -ForegroundColor Gray
Write-Host "Iterations: $Iterations" -ForegroundColor Gray
Write-Host ""

# Warm up
Invoke-ModuleScope {
    $null = Get-CleanCliGitInfo
    Start-Sleep -Milliseconds 100
}

$results = @()

# 1. Cold prompt (first call after cache clear)
$results += Measure-Operation "Cold Get-CleanCliGitInfo (cache clear)" {
    Invoke-ModuleScope {
        $script:CleanCliGitCache.Clear()
        Get-CleanCliGitInfo | Out-Null
    }
} -Iterations $Iterations

# 2. Warm prompt (cached, no changes)
$results += Measure-Operation "Warm Get-CleanCliGitInfo (cached, clean)" {
    Invoke-ModuleScope { Get-CleanCliGitInfo | Out-Null }
} -Iterations $Iterations

# 3. Warm prompt with changes (create temp file)
$results += Measure-Operation "Warm Get-CleanCliGitInfo (cached, dirty)" {
    Invoke-ModuleScope {
        $temp = [System.IO.Path]::GetTempFileName()
        Copy-Item $temp (Join-Path $TestRepo "__bench_temp_$([guid]::NewGuid()).tmp")
        Get-CleanCliGitInfo | Out-Null
        Remove-Item (Get-ChildItem $TestRepo "__bench_temp_*.tmp") -Force -ErrorAction SilentlyContinue
    }
} -Iterations $Iterations

# 4. Repo root detection (Find-CleanCliGitRepository)
$results += Measure-Operation "Find-CleanCliGitRepository" {
    Invoke-ModuleScope { Find-CleanCliGitRepository | Out-Null }
} -Iterations $Iterations

# 5. Git status invocation (Invoke-CleanCliGit)
$results += Measure-Operation "Invoke-CleanCliGit (status)" {
    Invoke-ModuleScope {
        $repo = Find-CleanCliGitRepository
        $args = Get-CleanCliGitStatusArguments
        Invoke-CleanCliGit -RepositoryRoot $repo.Root -Arguments $args | Out-Null
    }
} -Iterations $Iterations

# 6. Completion: commands (first call)
$results += Measure-Operation "Get-CleanCliGitCommands (cold)" {
    Invoke-ModuleScope {
        $script:CleanCliGitCompletionCache.Clear()
        Get-CleanCliGitCommands | Out-Null
    }
} -Iterations $Iterations

# 7. Completion: commands (warm)
$results += Measure-Operation "Get-CleanCliGitCommands (warm)" {
    Invoke-ModuleScope { Get-CleanCliGitCommands | Out-Null }
} -Iterations $Iterations

# 8. Completion: refs (first call)
$results += Measure-Operation "Get-CleanCliGitRefs (cold)" {
    Invoke-ModuleScope {
        $script:CleanCliGitCompletionCache.Clear()
        Get-CleanCliGitRefs | Out-Null
    }
} -Iterations $Iterations

# 9. Completion: refs (warm)
$results += Measure-Operation "Get-CleanCliGitRefs (warm)" {
    Invoke-ModuleScope { Get-CleanCliGitRefs | Out-Null }
} -Iterations $Iterations

# 10. Completion: full candidates (git switch fea<TAB>)
$results += Measure-Operation "Get-CleanCliGitCompletionCandidates (refs)" {
    Invoke-ModuleScope {
        $tokens = $null; $errors = $null
        $root = [System.Management.Automation.Language.Parser]::ParseInput('git switch fea', [ref]$tokens, [ref]$errors)
        $ast = $root.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        Get-CleanCliGitCompletionCandidates -WordToComplete 'fea' -CommandAst $ast | Out-Null
    }
} -Iterations $Iterations

# 11. Async refresh start
$results += Measure-Operation "Start-CleanCliGitAsyncRefresh" {
    Invoke-ModuleScope {
        $repo = Find-CleanCliGitRepository
        $key = Get-CleanCliGitCacheKey -Repository $repo -Path $TestRepo
        $args = Get-CleanCliGitStatusArguments
        Start-CleanCliGitAsyncRefresh -Repository $repo -CacheKey $key -Arguments $args
    }
} -Iterations $Iterations

# Output results
$results | Format-Table -AutoSize

# Summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | ForEach-Object {
    $color = if ($_.AvgMs -gt 50) { 'Red' } elseif ($_.AvgMs -gt 20) { 'Yellow' } else { 'Green' }
    Write-Host "$($_.Name.PadRight(50))  Avg: $($_.AvgMs.ToString().PadLeft(6))ms  P95: $($_.P95Ms.ToString().PadLeft(6))ms  P99: $($_.P99Ms.ToString().PadLeft(6))ms" -ForegroundColor $color
}