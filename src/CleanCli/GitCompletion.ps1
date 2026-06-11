function ConvertTo-CleanCliGitCompletionText {
    param([string]$Text)

    if ($Text -notmatch "[\s#@`$;,{}()']") {
        return $Text
    }

    "'$($Text.Replace("'", "''"))'"
}

function New-CleanCliGitCompletionResult {
    param(
        [string]$Text,
        [string]$ToolTip = $Text,
        [System.Management.Automation.CompletionResultType]$ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue
    )

    [System.Management.Automation.CompletionResult]::new(
        (ConvertTo-CleanCliGitCompletionText -Text $Text),
        $Text,
        $ResultType,
        $ToolTip
    )
}

function Get-CleanCliGitCompletionCacheValue {
    param(
        [string]$Key,
        [int]$MaxAgeMilliseconds
    )

    if (-not $script:CleanCliGitCompletionCache.ContainsKey($Key)) {
        return $null
    }

    $entry = $script:CleanCliGitCompletionCache[$Key]
    if (((Get-Date) - $entry.CreatedAt).TotalMilliseconds -gt $MaxAgeMilliseconds) {
        $script:CleanCliGitCompletionCache.Remove($Key)
        return $null
    }

    ,$entry.Value
}

function Set-CleanCliGitCompletionCacheValue {
    param(
        [string]$Key,
        [object]$Value
    )

    $script:CleanCliGitCompletionCache[$Key] = [pscustomobject]@{
        CreatedAt = Get-Date
        Value = $Value
    }
}

function Invoke-CleanCliGitCompletionCommand {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = (Get-Location).ProviderPath
    )

    $script:CleanCliState.GitCompletionProcessCount++
    if ($script:CleanCliGitCompletionCommand) {
        $result = & $script:CleanCliGitCompletionCommand $Arguments $WorkingDirectory
        if ($result -is [hashtable] -or $result -is [pscustomobject]) {
            if ($result.TimedOut) { $script:CleanCliState.GitCompletionTimeoutCount++ }
            return $result
        }
        return [pscustomobject]@{ Lines = @($result); TimedOut = $false; ExitCode = 0 }
    }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) {
        $git = Get-Command git -ErrorAction SilentlyContinue
    }
    if (-not $git) {
        return [pscustomobject]@{ Lines = @(); TimedOut = $false; ExitCode = -1 }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $git.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.Environment['GIT_OPTIONAL_LOCKS'] = '0'
    $startInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ Lines = @(); TimedOut = $false; ExitCode = -1 }
        }

        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($script:CleanCliGitCompletionTimeoutMilliseconds)) {
            $process.Kill($true)
            $script:CleanCliState.GitCompletionTimeoutCount++
            return [pscustomobject]@{ Lines = @(); TimedOut = $true; ExitCode = -1 }
        }

        $text = @($stdout.Result, $stderr.Result) -join "`n"
        [pscustomobject]@{
            Lines = @($text -split "`r?`n" | Where-Object { $_ })
            TimedOut = $false
            ExitCode = $process.ExitCode
        }
    }
    catch {
        [pscustomobject]@{ Lines = @(); TimedOut = $false; ExitCode = -1 }
    }
    finally {
        $process.Dispose()
    }
}

function Get-CleanCliGitCompletionVersion {
    $cached = Get-CleanCliGitCompletionCacheValue -Key 'git-version' -MaxAgeMilliseconds 3600000
    if ($null -ne $cached) { return [string]$cached }

    $result = Invoke-CleanCliGitCompletionCommand -Arguments @('--version')
    $version = if ($result.Lines.Count -gt 0) { [string]$result.Lines[0] } else { 'unknown' }
    Set-CleanCliGitCompletionCacheValue -Key 'git-version' -Value $version
    $version
}

function Get-CleanCliGitCommands {
    $version = Get-CleanCliGitCompletionVersion
    $key = "commands:$version"
    $cached = Get-CleanCliGitCompletionCacheValue -Key $key -MaxAgeMilliseconds 3600000
    if ($null -ne $cached) { return @($cached) }

    $result = Invoke-CleanCliGitCompletionCommand -Arguments @('help', '-a')
    $commands = New-Object System.Collections.Generic.List[string]
    foreach ($line in $result.Lines) {
        if ($line -match '^\s{3}([a-z0-9][a-z0-9-]+)\s{2,}') {
            $commands.Add($matches[1])
        }
    }

    $value = @($commands | Sort-Object -Unique)
    Set-CleanCliGitCompletionCacheValue -Key $key -Value $value
    $value
}

function Get-CleanCliGitAliases {
    $cached = Get-CleanCliGitCompletionCacheValue -Key 'aliases' -MaxAgeMilliseconds 1000
    if ($null -ne $cached) { return @($cached) }

    $result = Invoke-CleanCliGitCompletionCommand -Arguments @('config', '--get-regexp', '^alias\.')
    $aliases = foreach ($line in $result.Lines) {
        if ($line -match '^alias\.([^\s]+)\s+(.+)$') {
            [pscustomobject]@{ Name = $matches[1]; Expansion = $matches[2] }
        }
    }
    $value = @($aliases)
    Set-CleanCliGitCompletionCacheValue -Key 'aliases' -Value $value
    $value
}

function Resolve-CleanCliGitAlias {
    param([string]$Command)

    $alias = Get-CleanCliGitAliases | Where-Object Name -eq $Command | Select-Object -First 1
    if (-not $alias -or $alias.Expansion.StartsWith('!')) { return $Command }
    ($alias.Expansion -split '\s+', 2)[0]
}

function Get-CleanCliGitOptions {
    param([string]$Command)

    $version = Get-CleanCliGitCompletionVersion
    $key = "options:${version}:$Command"
    $cached = Get-CleanCliGitCompletionCacheValue -Key $key -MaxAgeMilliseconds 3600000
    if ($null -ne $cached) { return @($cached) }

    $result = Invoke-CleanCliGitCompletionCommand -Arguments @($Command, '-h')
    $options = foreach ($line in $result.Lines) {
        foreach ($match in [regex]::Matches($line, '--\[no-\]([a-z0-9][a-z0-9-]*)')) {
            "--$($match.Groups[1].Value)"
            "--no-$($match.Groups[1].Value)"
        }
        foreach ($match in [regex]::Matches($line, '(?<![\w-])(--[a-z0-9][a-z0-9-]*(?:=)?|-[A-Za-z0-9])(?![\w-])')) {
            $match.Groups[1].Value.TrimEnd('=')
        }
    }
    $value = @($options | Sort-Object -CaseSensitive -Unique)
    Set-CleanCliGitCompletionCacheValue -Key $key -Value $value
    $value
}

function Get-CleanCliGitRefs {
    param([string]$Kind = 'all')

    $key = "refs:${Kind}:$((Get-Location).ProviderPath)"
    $cached = Get-CleanCliGitCompletionCacheValue -Key $key -MaxAgeMilliseconds 1000
    if ($null -ne $cached) { return @($cached) }

    $prefixes = switch ($Kind) {
        'branches' { @('refs/heads', 'refs/remotes') }
        'tags' { @('refs/tags') }
        default { @('refs/heads', 'refs/remotes', 'refs/tags') }
    }
    $arguments = @('for-each-ref', '--format=%(refname:short)') + $prefixes
    $result = Invoke-CleanCliGitCompletionCommand -Arguments $arguments
    $value = @($result.Lines | Where-Object { $_ -and $_ -notmatch '/HEAD$' } | Sort-Object -Unique)
    Set-CleanCliGitCompletionCacheValue -Key $key -Value $value
    $value
}

function Get-CleanCliGitRemotes {
    $key = "remotes:$((Get-Location).ProviderPath)"
    $cached = Get-CleanCliGitCompletionCacheValue -Key $key -MaxAgeMilliseconds 1000
    if ($null -ne $cached) { return @($cached) }
    $result = Invoke-CleanCliGitCompletionCommand -Arguments @('remote')
    $value = @($result.Lines | Sort-Object -Unique)
    Set-CleanCliGitCompletionCacheValue -Key $key -Value $value
    $value
}

function Get-CleanCliGitStashes {
    $result = Invoke-CleanCliGitCompletionCommand -Arguments @('stash', 'list', '--format=%gd')
    @($result.Lines | Sort-Object -Unique)
}

function Get-CleanCliGitFiles {
    param(
        [string]$Command,
        [string[]]$Elements
    )

    $arguments = switch ($Command) {
        'add' { @('ls-files', '--modified', '--deleted', '--others', '--exclude-standard') }
        'rm' { @('ls-files') }
        'restore' {
            if ($Elements -contains '--staged' -or $Elements -contains '-S') {
                @('diff', '--cached', '--name-only', '--diff-filter=ACDMRTUXB')
            }
            else { @('diff', '--name-only', '--diff-filter=DMRTUXB') }
        }
        'checkout' { @('diff', '--name-only', '--diff-filter=DMRTUXB') }
        'diff' { @('diff', '--name-only', '--diff-filter=ACDMRTUXB') }
        default { return @() }
    }
    $result = Invoke-CleanCliGitCompletionCommand -Arguments $arguments
    @($result.Lines | Sort-Object -Unique)
}

function Get-CleanCliGitCompletionElements {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    @($CommandAst.CommandElements | ForEach-Object {
        if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value }
        else { $_.Extent.Text }
    })
}

function Get-CleanCliGitCompletionCandidates {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $elements = Get-CleanCliGitCompletionElements -CommandAst $CommandAst
    if ($elements.Count -lt 2 -or ($elements.Count -eq 2 -and $WordToComplete)) {
        $script:CleanCliState.LastGitCompletionCategory = 'command'
        $names = @(Get-CleanCliGitCommands) + @(Get-CleanCliGitAliases | ForEach-Object Name)
        return @($names | Where-Object { $_ -like "$WordToComplete*" } | Sort-Object -Unique)
    }

    $command = Resolve-CleanCliGitAlias -Command $elements[1]
    if ($WordToComplete -match '^--source=(.*)$' -and $command -eq 'restore') {
        $script:CleanCliState.LastGitCompletionCategory = 'ref'
        return @(Get-CleanCliGitRefs | Where-Object { $_ -like "$($matches[1])*" } | ForEach-Object { "--source=$_" })
    }
    if ($WordToComplete -match '^--(untracked-files|ignore-submodules|recurse-submodules|conflict|color|cleanup)=(.*)$') {
        $values = switch ($matches[1]) {
            'untracked-files' { @('no', 'normal', 'all') }
            'ignore-submodules' { @('none', 'untracked', 'dirty', 'all') }
            'recurse-submodules' { @('yes', 'on-demand', 'no') }
            'conflict' { @('merge', 'diff3', 'zdiff3') }
            'color' { @('always', 'never', 'auto') }
            'cleanup' { @('strip', 'whitespace', 'verbatim', 'scissors', 'default') }
        }
        $name = $matches[1]
        $valuePrefix = $matches[2]
        $script:CleanCliState.LastGitCompletionCategory = 'option-value'
        return @($values | Where-Object { $_ -like "$valuePrefix*" } | ForEach-Object { "--$name=$_" })
    }
    if ($WordToComplete.StartsWith('-')) {
        $script:CleanCliState.LastGitCompletionCategory = 'option'
        return @(Get-CleanCliGitOptions -Command $command | Where-Object { $_ -like "$WordToComplete*" })
    }

    $previous = if ($elements.Count -gt 2) { $elements[$elements.Count - 2] } else { '' }
    $candidates = switch ($command) {
        { $_ -in @('switch', 'branch', 'merge', 'rebase', 'reset', 'revert', 'cherry-pick', 'show', 'log') } {
            $script:CleanCliState.LastGitCompletionCategory = 'ref'
            Get-CleanCliGitRefs
        }
        'checkout' {
            if ($elements -contains '--') {
                $script:CleanCliState.LastGitCompletionCategory = 'file'
                Get-CleanCliGitFiles -Command checkout -Elements $elements
            }
            else {
                $script:CleanCliState.LastGitCompletionCategory = 'ref'
                Get-CleanCliGitRefs
            }
        }
        'restore' {
            if ($previous -eq '--source' -or $previous -eq '-s' -or $WordToComplete -like '--source=*') {
                $script:CleanCliState.LastGitCompletionCategory = 'ref'
                Get-CleanCliGitRefs
            }
            else {
                $script:CleanCliState.LastGitCompletionCategory = 'file'
                Get-CleanCliGitFiles -Command restore -Elements $elements
            }
        }
        { $_ -in @('add', 'rm', 'diff') } {
            $script:CleanCliState.LastGitCompletionCategory = 'file'
            Get-CleanCliGitFiles -Command $command -Elements $elements
        }
        { $_ -in @('push', 'pull', 'fetch') } {
            if ($elements.Count -eq 2 -or ($elements.Count -eq 3 -and $WordToComplete)) {
                $script:CleanCliState.LastGitCompletionCategory = 'remote'
                Get-CleanCliGitRemotes
            }
            else {
                $script:CleanCliState.LastGitCompletionCategory = 'ref'
                Get-CleanCliGitRefs
            }
        }
        'stash' {
            if ($elements.Count -eq 2 -or ($elements.Count -eq 3 -and $WordToComplete)) { @('apply', 'branch', 'clear', 'create', 'drop', 'list', 'pop', 'push', 'show') }
            else { Get-CleanCliGitStashes }
            $script:CleanCliState.LastGitCompletionCategory = 'stash'
        }
        'worktree' {
            $script:CleanCliState.LastGitCompletionCategory = 'worktree'
            if ($elements.Count -eq 2 -or ($elements.Count -eq 3 -and $WordToComplete)) { @('add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock') }
            elseif ($elements[2] -eq 'add' -and $elements.Count -gt 3) { Get-CleanCliGitRefs -Kind branches }
            else { @() }
        }
        'sparse-checkout' { @('add', 'check-rules', 'disable', 'init', 'list', 'reapply', 'set'); $script:CleanCliState.LastGitCompletionCategory = 'subcommand' }
        'maintenance' { @('register', 'run', 'start', 'stop', 'unregister'); $script:CleanCliState.LastGitCompletionCategory = 'subcommand' }
        'config' {
            $script:CleanCliState.LastGitCompletionCategory = 'config'
            @('--global', '--local', '--system', '--worktree')
        }
        default { @() }
    }

    @($candidates | Where-Object { $_ -like "$WordToComplete*" } | Sort-Object -Unique)
}

function Invoke-CleanCliGitCompletion {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    if (-not $script:CleanCliState.Enabled -or -not $script:CleanCliOptions.GitCompletionEnabled) {
        return
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($candidate in Get-CleanCliGitCompletionCandidates -WordToComplete $WordToComplete -CommandAst $CommandAst) {
            New-CleanCliGitCompletionResult -Text $candidate -ToolTip "git $candidate completion"
        }
    }
    finally {
        $stopwatch.Stop()
        $script:CleanCliState.LastGitCompletionMilliseconds = $stopwatch.Elapsed.TotalMilliseconds
    }
}

function Register-CleanCliGitCompletion {
    if ($script:CleanCliState.GitCompletionRegistered) { return }
    if (-not (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue)) { return }

    Register-ArgumentCompleter -Native -CommandName git, git.exe -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        Invoke-CleanCliGitCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
    }
    $script:CleanCliState.GitCompletionRegistered = $true
}
