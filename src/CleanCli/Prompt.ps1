function Resolve-CleanCliPromptSymbol {
    param(
        [string]$Value,
        [string]$DefaultValue
    )

    if ($Value -and $Value -ne 'auto') {
        return $Value
    }

    $DefaultValue
}

function Get-CleanCliSymbols {
    $options = Get-CleanCliOption

    if ($env:CLEANCLI_ASCII -eq '1' -or $options.AsciiMode) {
        return [pscustomobject]@{
            Separator = Resolve-CleanCliPromptSymbol -Value $options.PromptSeparator -DefaultValue '>'
            Branch = Resolve-CleanCliPromptSymbol -Value $options.GitSymbol -DefaultValue 'git:'
            Dirty = Resolve-CleanCliPromptSymbol -Value $options.DirtySymbol -DefaultValue '*'
            Path = Resolve-CleanCliPromptSymbol -Value $options.PathSymbol -DefaultValue 'dir:'
            Admin = Resolve-CleanCliPromptSymbol -Value $options.AdminSymbol -DefaultValue 'admin'
            Time = Resolve-CleanCliPromptSymbol -Value $options.TimeSymbol -DefaultValue 'time:'
            Success = '+'
            Error = '!'
        }
    }

    [pscustomobject]@{
        Separator = Resolve-CleanCliPromptSymbol -Value $options.PromptSeparator -DefaultValue ([string][char]0xe0b0)
        Branch = Resolve-CleanCliPromptSymbol -Value $options.GitSymbol -DefaultValue ([string][char]0xe0a0)
        Dirty = Resolve-CleanCliPromptSymbol -Value $options.DirtySymbol -DefaultValue ([string][char]0xf044)
        Path = Resolve-CleanCliPromptSymbol -Value $options.PathSymbol -DefaultValue ([string][char]0xe5ff)
        Admin = Resolve-CleanCliPromptSymbol -Value $options.AdminSymbol -DefaultValue ([string][char]0xf0e7)
        Time = Resolve-CleanCliPromptSymbol -Value $options.TimeSymbol -DefaultValue ([string][char]0xf017)
        Success = [string][char]0x2713
        Error = [string][char]0x2717
    }
}

function New-CleanCliAdminSegment {
    $options = Get-CleanCliOption
    $symbols = Get-CleanCliSymbols
    New-CleanCliSegment -Text $symbols.Admin -Foreground $options.AdminForeground -Background $options.AdminBackground
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
        $Path = '~' + $Path.Substring($homePath.Length)
    }

    $options = Get-CleanCliOption
    if ($options.PathDisplayMode -eq 'full') {
        return $Path
    }

    if ($options.PathDisplayMode -eq 'auto' -and $Path.Length -le 48) {
        return $Path
    }

    ConvertTo-CleanCliCompactPath -Path $Path
}

function ConvertTo-CleanCliCompactPath {
    param([string]$Path)

    $separator = if ($Path.Contains('\')) { '\' } else { '/' }
    $escapedSeparator = [regex]::Escape($separator)
    $segments = $Path -split $escapedSeparator | Where-Object { $_ -ne '' }
    if ($segments.Count -le 4) {
        return $Path
    }

    $first = $segments[0]
    $second = $segments[1]
    $parent = $segments[$segments.Count - 2]
    $leaf = ConvertTo-CleanCliCompactPathLeaf -Leaf $segments[$segments.Count - 1]

    if ($first -eq '~') {
        return ($first, $second, '...', $parent, $leaf) -join $separator
    }

    return ($first, '...', $parent, $leaf) -join $separator
}

function ConvertTo-CleanCliCompactPathLeaf {
    param([string]$Leaf)

    if ($Leaf.Length -le 24) {
        return $Leaf
    }

    if ($Leaf -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $Leaf.Substring(0, 8) + '...'
    }

    $Leaf.Substring(0, 21) + '...'
}

function New-CleanCliSegment {
    param(
        [string]$Text,
        [string]$Foreground = 'White',
        [string]$Background = 'DarkGray'
    )

    [pscustomobject]@{
        Text = $Text
        Foreground = $Foreground
        Background = $Background
    }
}

function Get-CleanCliAnsiCode {
    param(
        [string]$Color,
        [switch]$Background
    )

    if ($Background) {
        switch ($Color) {
            'Black' { 40 }
            'Red' { 41 }
            'Green' { 42 }
            'Yellow' { 43 }
            'Blue' { 44 }
            'Magenta' { 45 }
            'Cyan' { 46 }
            'White' { 47 }
            'DarkGray' { 100 }
            'Default' { 49 }
            default { 100 }
        }
        return
    }

    switch ($Color) {
        'Black' { 30 }
        'Red' { 31 }
        'Green' { 32 }
        'Yellow' { 33 }
        'Blue' { 34 }
        'Magenta' { 35 }
        'Cyan' { 36 }
        'White' { 37 }
        'DarkGray' { 90 }
        'Default' { 39 }
        default { 37 }
    }
}

function Format-CleanCliSegment {
    param([object]$Segment)

    if ($env:NO_COLOR) {
        return " $($Segment.Text) "
    }

    $escape = [char]27
    $fgCode = Get-CleanCliAnsiCode -Color $Segment.Foreground
    $bgCode = Get-CleanCliAnsiCode -Color $Segment.Background -Background

    "$escape[${fgCode};${bgCode}m $($Segment.Text) $escape[0m"
}

function Format-CleanCliSeparator {
    param(
        [string]$Foreground,
        [string]$Background,
        [string]$Text
    )

    if ($env:NO_COLOR) {
        return $Text
    }

    $escape = [char]27
    $fgCode = Get-CleanCliAnsiCode -Color $Foreground
    $bgCode = Get-CleanCliAnsiCode -Color $Background -Background
    "$escape[${fgCode};${bgCode}m$Text$escape[0m"
}

function Format-CleanCliPromptSegments {
    param([object[]]$Segments)

    if (-not $Segments -or $Segments.Count -eq 0) {
        return ''
    }

    $symbols = Get-CleanCliSymbols
    $parts = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $Segments.Count; $index++) {
        $segment = $Segments[$index]
        $parts.Add((Format-CleanCliSegment -Segment $segment))
        if ($index -lt ($Segments.Count - 1)) {
            $next = $Segments[$index + 1]
            $parts.Add((Format-CleanCliSeparator -Foreground $segment.Background -Background $next.Background -Text $symbols.Separator))
        }
    }

    $last = $Segments[$Segments.Count - 1]
    $parts.Add((Format-CleanCliSeparator -Foreground $last.Background -Background 'Default' -Text $symbols.Separator))
    ($parts -join '') + ' '
}

function Get-CleanCliVisiblePromptLength {
    param([string]$PromptText)

    if (-not $PromptText) {
        return 0
    }

    (($PromptText -replace "`e\[[0-9;]*m", '')).Length
}

function Get-CleanCliConsoleWidth {
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
            return $Host.UI.RawUI.WindowSize.Width
        }
    }
    catch {
    }

    try {
        return [Console]::WindowWidth
    }
    catch {
        return 0
    }
}

function Test-CleanCliRightPromptSupported {
    if ($env:NO_COLOR) {
        return $false
    }

    (Get-CleanCliConsoleWidth) -gt 0
}

function Format-CleanCliRightPrompt {
    param(
        [string]$LeftText,
        [string]$RightText,
        [int]$Width = (Get-CleanCliConsoleWidth)
    )

    if (-not $RightText -or $Width -le 0) {
        return ''
    }

    $escape = [char]27
    $visibleRight = Get-CleanCliVisiblePromptLength -PromptText $RightText
    $column = [Math]::Max(1, $Width - $visibleRight + 1)
    "$escape[s$escape[${column}G$RightText$escape[u"
}

function Test-CleanCliTwoLinePrompt {
    param(
        [string]$PromptText,
        [object]$Options
    )

    if ($Options.PromptLayout -eq 'two-line') {
        return $true
    }

    if ($Options.PromptLayout -eq 'auto') {
        return (Get-CleanCliVisiblePromptLength -PromptText $PromptText) -gt 96
    }

    $false
}

function Format-CleanCliCommandDuration {
    param([double]$Milliseconds)

    if ($Milliseconds -lt 1000) {
        return "$([math]::Round($Milliseconds))ms"
    }

    $duration = [timespan]::FromMilliseconds($Milliseconds)
    if ($duration.TotalHours -ge 1) {
        return '{0}h {1}m' -f [math]::Floor($duration.TotalHours), $duration.Minutes
    }

    if ($duration.TotalMinutes -ge 1) {
        return '{0}m {1}s' -f [math]::Floor($duration.TotalMinutes), $duration.Seconds
    }

    '{0:0.#}s' -f $duration.TotalSeconds
}

function Get-CleanCliLastCommandDurationMilliseconds {
    if ($script:CleanCliCommandDurationProvider) {
        return & $script:CleanCliCommandDurationProvider
    }

    $history = Get-History -Count 1 -ErrorAction SilentlyContinue
    if (-not $history -or -not $history.StartExecutionTime -or -not $history.EndExecutionTime) {
        return $null
    }

    ($history.EndExecutionTime - $history.StartExecutionTime).TotalMilliseconds
}

function Get-CleanCliCommandDurationPromptText {
    param([object]$Options)

    $milliseconds = Get-CleanCliLastCommandDurationMilliseconds
    if ($null -eq $milliseconds -or $milliseconds -lt $Options.CommandDurationThresholdMilliseconds) {
        return ''
    }

    $symbols = Get-CleanCliSymbols
    '{0} {1}' -f $symbols.Time, (Format-CleanCliCommandDuration -Milliseconds $milliseconds)
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
        $summary = Get-CleanCliObjectValue -Object $Git -Name StatusSummary -DefaultValue ''
        if ($summary) {
            $parts += "$($symbols.Dirty) $summary"
        }
        else {
            $changes = $Git.Working + $Git.Staged + $Git.Untracked
            if ($changes -gt 0) {
                $parts += "$($symbols.Dirty) $changes"
            }
            else {
                $parts += $symbols.Dirty
            }
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
        $segments = New-Object System.Collections.Generic.List[object]
        if (Test-CleanCliAdministrator) {
            $segments.Add((New-CleanCliAdminSegment))
        }

        $pathText = '{0} {1}' -f $symbols.Path, (Get-CleanCliShortPath)
        $segments.Add((New-CleanCliSegment -Text $pathText -Foreground $options.PathForeground -Background $options.PathBackground))

        $rightSegments = New-Object System.Collections.Generic.List[object]
        $useRightPrompt = $options.RightPrompt -and (Test-CleanCliRightPromptSupported)

        $git = Get-CleanCliGitInfo
        $gitText = Get-CleanCliGitPromptText -Git $git
        if ($gitText) {
            if ($useRightPrompt) {
                $rightSegments.Add((New-CleanCliSegment -Text $gitText -Foreground $options.GitForeground -Background $options.GitBackground))
            }
            else {
                $segments.Add((New-CleanCliSegment -Text $gitText -Foreground $options.GitForeground -Background $options.GitBackground))
            }
        }

        $durationText = Get-CleanCliCommandDurationPromptText -Options $options
        if ($durationText) {
            if ($useRightPrompt) {
                $rightSegments.Add((New-CleanCliSegment -Text $durationText -Foreground $options.TimeForeground -Background $options.TimeBackground))
            }
            else {
                $segments.Add((New-CleanCliSegment -Text $durationText -Foreground $options.TimeForeground -Background $options.TimeBackground))
            }
        }

        $promptText = Format-CleanCliPromptSegments -Segments $segments
        if ($useRightPrompt -and $rightSegments.Count -gt 0) {
            $rightPromptText = (Format-CleanCliPromptSegments -Segments $rightSegments).TrimEnd()
            $promptText += Format-CleanCliRightPrompt -LeftText $promptText -RightText $rightPromptText
        }

        if (Test-CleanCliTwoLinePrompt -PromptText $promptText -Options $options) {
            $promptText = $promptText.TrimEnd() + "`n$($symbols.Separator) "
        }
        elseif ($options.TransientPrompt) {
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
