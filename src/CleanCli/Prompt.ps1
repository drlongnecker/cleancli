function Get-CleanCliSymbols {
    $options = Get-CleanCliOption
    if ($env:CLEANCLI_ASCII -eq '1' -or $options.AsciiMode) {
        return [pscustomobject]@{
            Separator = '>'
            Branch = 'git:'
            Dirty = '*'
            Path = 'dir:'
            Admin = 'admin'
            Success = '+'
            Error = '!'
        }
    }

    [pscustomobject]@{
        Separator = [string][char]0xe0b0
        Branch = [string][char]0xe0a0
        Dirty = [string][char]0xf044
        Path = [string][char]0xe5ff
        Admin = [string][char]0xf0e7
        Success = [string][char]0x2713
        Error = [string][char]0x2717
    }
}

function Test-CleanCliAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CleanCliShortPath {
    param([string]$Path = (Get-Location).Path)

    if (-not $Path) {
        return ''
    }

    $homePath = [Environment]::GetFolderPath('UserProfile')
    if ($homePath -and $Path.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) {
        return '~' + $Path.Substring($homePath.Length)
    }

    $Path
}

function Format-CleanCliSegment {
    param(
        [string]$Text,
        [string]$Foreground = 'White',
        [string]$Background = 'DarkGray'
    )

    if ($env:NO_COLOR) {
        return " $Text "
    }

    $escape = [char]27
    $fgCode = switch ($Foreground) {
        'Black' { 30 }
        'Red' { 31 }
        'Green' { 32 }
        'Yellow' { 33 }
        'Blue' { 34 }
        'Magenta' { 35 }
        'Cyan' { 36 }
        default { 37 }
    }
    $bgCode = switch ($Background) {
        'Black' { 40 }
        'Red' { 41 }
        'Green' { 42 }
        'Yellow' { 43 }
        'Blue' { 44 }
        'Magenta' { 45 }
        'Cyan' { 46 }
        default { 100 }
    }

    "$escape[${fgCode};${bgCode}m $Text $escape[0m"
}

function Get-CleanCliGitPromptText {
    param([object]$Git)

    if (-not $Git -or -not $Git.IsRepository) {
        return ''
    }

    $symbols = Get-CleanCliSymbols
    $parts = @("$($symbols.Branch) $($Git.Branch)")
    if ($Git.Ahead -gt 0) {
        $parts += "+$($Git.Ahead)"
    }
    if ($Git.Behind -gt 0) {
        $parts += "-$($Git.Behind)"
    }
    if ($Git.Dirty) {
        $changes = $Git.Working + $Git.Staged + $Git.Untracked
        if ($changes -gt 0) {
            $parts += "$($symbols.Dirty) $changes"
        }
        else {
            $parts += $symbols.Dirty
        }
    }
    if ($Git.TimedOut) {
        $parts += 'slow'
    }

    $parts -join ' '
}

function Invoke-CleanCliPrompt {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastExitCode = $global:LASTEXITCODE
    $lastSuccess = $?
    $options = Get-CleanCliOption
    $symbols = Get-CleanCliSymbols

    try {
        $segments = New-Object System.Collections.Generic.List[string]
        if (Test-CleanCliAdministrator) {
            $segments.Add((Format-CleanCliSegment -Text $symbols.Admin -Foreground Yellow -Background Black))
        }

        $pathText = '{0} {1}' -f $symbols.Path, (Get-CleanCliShortPath)
        $segments.Add((Format-CleanCliSegment -Text $pathText -Foreground White -Background Magenta))

        $git = Get-CleanCliGitInfo
        $gitText = Get-CleanCliGitPromptText -Git $git
        if ($gitText) {
            $segments.Add((Format-CleanCliSegment -Text $gitText -Foreground Black -Background Green))
        }

        $promptText = ($segments -join $symbols.Separator) + ' '
        if ($options.TransientPrompt) {
            $promptText = $promptText.TrimEnd() + "`n"
        }

        $promptText
    }
    finally {
        $timer.Stop()
        $script:CleanCliState.LastPromptMilliseconds = $timer.Elapsed.TotalMilliseconds
        $global:LASTEXITCODE = $lastExitCode
    }
}
