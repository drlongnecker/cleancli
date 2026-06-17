function ConvertTo-CleanCliDuration {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -notmatch '^(?<count>\d+)(?<unit>ms|s|m|h|d|w)?$') {
        throw "Duration '$Value' must use a number with optional unit ms, s, m, h, d, or w."
    }

    $count = [double]$matches.count
    switch ($matches.unit) {
        'ms' { return [timespan]::FromMilliseconds($count) }
        's' { return [timespan]::FromSeconds($count) }
        'm' { return [timespan]::FromMinutes($count) }
        'h' { return [timespan]::FromHours($count) }
        'w' { return [timespan]::FromDays($count * 7) }
        default { return [timespan]::FromDays($count) }
    }
}

function ConvertTo-CleanCliSizeBytes {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -notmatch '^(?<count>\d+)(?<unit>b|kb|k|mb|m|gb|g)?$') {
        throw "Size '$Value' must use a number with optional unit b, kb, mb, or gb."
    }

    $count = [int64]$matches.count
    $unit = if ($matches.unit) { $matches.unit.ToLowerInvariant() } else { '' }
    switch ($unit) {
        { $_ -in @('k', 'kb') } { return $count * 1KB }
        { $_ -in @('m', 'mb') } { return $count * 1MB }
        { $_ -in @('g', 'gb') } { return $count * 1GB }
        default { return $count }
    }
}

function New-CleanCliListingQuery {
    param(
        [switch]$File,
        [switch]$Directory,
        [switch]$Symlink,
        [switch]$Empty,
        [switch]$NonEmpty,
        [string]$ModifiedWithin,
        [string]$ModifiedBefore,
        [string]$AccessedWithin,
        [string]$AccessedBefore,
        [string]$LargerThan,
        [string]$SmallerThan,
        [string]$NameLike,
        [string[]]$Extension,
        [string]$Sort,
        [switch]$Descending,
        [int]$First,
        [int]$Last,
        [string]$Qualifier
    )

    $query = [ordered]@{
        TypeFilters = @()
        EmptyFilters = @()
        ModifiedWithin = $null
        ModifiedBefore = $null
        AccessedWithin = $null
        AccessedBefore = $null
        LargerThan = $null
        SmallerThan = $null
        NameLike = ''
        Extensions = @()
        Sort = ''
        Descending = $false
        SliceStart = $null
        SliceEnd = $null
        HasCriteria = $false
    }

    if ($Qualifier) {
        Merge-CleanCliListingQuery -Target $query -Source (ConvertFrom-CleanCliQualifier -Qualifier $Qualifier) -PreferSourceSort
    }

    if ($File) { $query.TypeFilters += 'file'; $query.HasCriteria = $true }
    if ($Directory) { $query.TypeFilters += 'directory'; $query.HasCriteria = $true }
    if ($Symlink) { $query.TypeFilters += 'symlink'; $query.HasCriteria = $true }
    if ($Empty) { $query.EmptyFilters += $true; $query.HasCriteria = $true }
    if ($NonEmpty) { $query.EmptyFilters += $false; $query.HasCriteria = $true }
    if ($ModifiedWithin) { $query.ModifiedWithin = ConvertTo-CleanCliDuration -Value $ModifiedWithin; $query.HasCriteria = $true }
    if ($ModifiedBefore) { $query.ModifiedBefore = ConvertTo-CleanCliDuration -Value $ModifiedBefore; $query.HasCriteria = $true }
    if ($AccessedWithin) { $query.AccessedWithin = ConvertTo-CleanCliDuration -Value $AccessedWithin; $query.HasCriteria = $true }
    if ($AccessedBefore) { $query.AccessedBefore = ConvertTo-CleanCliDuration -Value $AccessedBefore; $query.HasCriteria = $true }
    if ($LargerThan) { $query.LargerThan = ConvertTo-CleanCliSizeBytes -Value $LargerThan; $query.HasCriteria = $true }
    if ($SmallerThan) { $query.SmallerThan = ConvertTo-CleanCliSizeBytes -Value $SmallerThan; $query.HasCriteria = $true }
    if ($NameLike) { $query.NameLike = $NameLike; $query.HasCriteria = $true }
    if ($Extension) {
        $query.Extensions = @($Extension | ForEach-Object {
            $value = ([string]$_).Trim()
            if (-not $value) { return }
            if ($value.StartsWith('.')) { $value.ToLowerInvariant() } else { ".$($value.ToLowerInvariant())" }
        })
        if ($query.Extensions.Count -gt 0) { $query.HasCriteria = $true }
    }
    if ($Sort) {
        $query.Sort = $Sort
        $query.Descending = [bool]$Descending
        $query.HasCriteria = $true
    }
    elseif ($Descending) {
        $query.Descending = $true
        $query.HasCriteria = $true
    }
    if ($First -gt 0) {
        $query.SliceStart = 1
        $query.SliceEnd = $First
        $query.HasCriteria = $true
    }
    if ($Last -gt 0) {
        $query.SliceStart = -$Last
        $query.SliceEnd = -1
        $query.HasCriteria = $true
    }

    [pscustomobject]$query
}

function Resolve-CleanCliListingInput {
    param(
        [string]$Path,
        [string]$Qualifier
    )

    if ($Qualifier -or -not $Path -or $Path -eq '.') {
        return [pscustomobject]@{
            Path = $Path
            Qualifier = $Qualifier
            NameLike = ''
            FileOnly = $false
        }
    }

    if (Test-Path -LiteralPath $Path) {
        return [pscustomobject]@{
            Path = $Path
            Qualifier = $Qualifier
            NameLike = ''
            FileOnly = $false
        }
    }

    if ($Path[0] -in @('/', '.', '@', '^', '[') -and -not $Path.StartsWith('.\') -and -not $Path.StartsWith('./')) {
        return [pscustomobject]@{
            Path = '.'
            Qualifier = $Path
            NameLike = ''
            FileOnly = $false
        }
    }

    if ($Path[0] -eq '*' -and $Path.Length -gt 1 -and $Path[1] -ne '.') {
        return [pscustomobject]@{
            Path = '.'
            Qualifier = $Path
            NameLike = ''
            FileOnly = $false
        }
    }

    if ($Path.IndexOfAny([char[]]@('*', '?')) -ge 0) {
        $parentPath = Split-Path -Path $Path -Parent
        $nameLike = Split-Path -Path $Path -Leaf
        if (-not $parentPath) {
            $parentPath = '.'
            $nameLike = $Path
        }
        return [pscustomobject]@{
            Path = $parentPath
            Qualifier = $Qualifier
            NameLike = $nameLike
            FileOnly = [bool]($nameLike -match '^\*\.[^\\/:*?"<>|]+$')
        }
    }

    [pscustomobject]@{
        Path = $Path
        Qualifier = $Qualifier
        NameLike = ''
        FileOnly = $false
    }
}

function Get-CleanCliChildItemLiteral {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Force,
        [switch]$Recurse,
        [int]$Depth = -1,
        [switch]$Directory
    )

    $parameters = @{
        LiteralPath = $Path
    }
    if ($Force) { $parameters.Force = $true }
    if ($Recurse) { $parameters.Recurse = $true }
    if ($Directory) { $parameters.Directory = $true }
    if ($Recurse -and $Depth -ge 0) { $parameters.Depth = $Depth }

    @(Get-ChildItem @parameters)
}

function Get-CleanCliRelativeListingPath {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -le $root.Length) {
        return './'
    }

    $relative = $full.Substring($root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    "./$($relative.Replace('\', '/'))"
}

function Get-CleanCliRecursiveSearchDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Force,
        [int]$Depth = -1,
        [string]$RecurseDirectory
    )

    if (-not $RecurseDirectory) {
        return @([pscustomobject]@{
            FullName = (Resolve-Path -LiteralPath $Path).ProviderPath
            SearchDepth = $Depth
        })
    }

    $selector = $RecurseDirectory.Replace('\', '/')
    $hasPathSelector = $selector.IndexOf('/') -ge 0
    $directories = if ($hasPathSelector) {
        Get-CleanCliChildItemLiteral -Path $Path -Force:$Force -Recurse -Depth $Depth -Directory
    }
    else {
        Get-CleanCliChildItemLiteral -Path $Path -Force:$Force -Directory
    }

    foreach ($directory in $directories) {
        $matched = if ($hasPathSelector) {
            (Get-CleanCliRelativeListingPath -RootPath $Path -Path $directory.FullName) -like $selector
        }
        else {
            $directory.Name -like $selector
        }

        if ($matched) {
            [pscustomobject]@{
                FullName = $directory.FullName
                SearchDepth = 0
            }
        }
    }
}

function Get-CleanCliListingItems {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Force,
        [switch]$Recurse,
        [int]$Depth = -1,
        [string]$RecurseDirectory
    )

    if (-not $Recurse) {
        return Get-CleanCliChildItemLiteral -Path $Path -Force:$Force
    }

    $directories = @(Get-CleanCliRecursiveSearchDirectory -Path $Path -Force:$Force -Depth $Depth -RecurseDirectory $RecurseDirectory)
    $items = foreach ($directory in $directories) {
        $searchDepth = [int]$directory.SearchDepth
        Get-CleanCliChildItemLiteral -Path $directory.FullName -Force:$Force -Recurse:($searchDepth -ne 0) -Depth $searchDepth
    }

    @($items)
}

function Merge-CleanCliListingQuery {
    param(
        [System.Collections.IDictionary]$Target,
        [object]$Source,
        [switch]$PreferSourceSort
    )

    $Target.TypeFilters += @($Source.TypeFilters)
    $Target.EmptyFilters += @($Source.EmptyFilters)
    foreach ($name in @('ModifiedWithin', 'ModifiedBefore', 'AccessedWithin', 'AccessedBefore', 'LargerThan', 'SmallerThan', 'NameLike')) {
        if ($null -ne $Source.$name -and $Source.$name -ne '') {
            $Target[$name] = $Source.$name
        }
    }
    if ($Source.Extensions.Count -gt 0) {
        $Target.Extensions += @($Source.Extensions)
    }
    if ($PreferSourceSort -and $Source.Sort) {
        $Target.Sort = $Source.Sort
        $Target.Descending = [bool]$Source.Descending
    }
    if ($null -ne $Source.SliceStart) {
        $Target.SliceStart = $Source.SliceStart
        $Target.SliceEnd = $Source.SliceEnd
    }
    if ($Source.HasCriteria) {
        $Target.HasCriteria = $true
    }
}

function ConvertFrom-CleanCliQualifier {
    param(
        [Parameter(Mandatory)]
        [string]$Qualifier
    )

    $query = [ordered]@{
        TypeFilters = @()
        EmptyFilters = @()
        ModifiedWithin = $null
        ModifiedBefore = $null
        AccessedWithin = $null
        AccessedBefore = $null
        LargerThan = $null
        SmallerThan = $null
        NameLike = ''
        Extensions = @()
        Sort = ''
        Descending = $false
        SliceStart = $null
        SliceEnd = $null
        HasCriteria = $false
    }

    $index = 0
    $negate = $false
    while ($index -lt $Qualifier.Length) {
        $char = $Qualifier[$index]
        if (Test-CleanCliQualifierNamePatternStart -Qualifier $Qualifier -Index $index -Negate:$negate) {
            $query.NameLike = $Qualifier.Substring($index)
            $query.HasCriteria = $true
            $index = $Qualifier.Length
            continue
        }

        switch ($char) {
            '*' {
                $index++
                continue
            }
            '^' {
                $negate = -not $negate
                $index++
                continue
            }
            '/' {
                Add-CleanCliQualifierType -Query $query -Type directory -Negate:$negate
                $negate = $false
                $index++
                continue
            }
            '.' {
                Add-CleanCliQualifierType -Query $query -Type file -Negate:$negate
                $negate = $false
                $index++
                continue
            }
            '@' {
                Add-CleanCliQualifierType -Query $query -Type symlink -Negate:$negate
                $negate = $false
                $index++
                continue
            }
            'F' {
                $query.EmptyFilters += [bool]$negate
                $query.HasCriteria = $true
                $negate = $false
                $index++
                continue
            }
            { $_ -in @('m', 'a') } {
                if (-not (Test-CleanCliQualifierTimeTokenStart -Qualifier $Qualifier -Index $index)) {
                    throw "Qualifier '$char' in '$Qualifier' must include '-' for within or '+' for before."
                }
                $index = Read-CleanCliQualifierTime -Qualifier $Qualifier -Index $index -Query $query -Negate:$negate
                $negate = $false
                continue
            }
            'L' {
                if (-not (Test-CleanCliQualifierSizeTokenStart -Qualifier $Qualifier -Index $index)) {
                    throw "Qualifier 'L' in '$Qualifier' must include '-' for smaller or '+' for larger."
                }
                $index = Read-CleanCliQualifierSize -Qualifier $Qualifier -Index $index -Query $query -Negate:$negate
                $negate = $false
                continue
            }
            { $_ -in @('o', 'O') } {
                if ($negate) {
                    throw "Qualifier '^$char' is not supported for sorting."
                }
                $index = Read-CleanCliQualifierSort -Qualifier $Qualifier -Index $index -Query $query
                continue
            }
            '[' {
                if ($negate) {
                    throw "Qualifier '^[' is not supported for slicing."
                }
                $index = Read-CleanCliQualifierSlice -Qualifier $Qualifier -Index $index -Query $query
                continue
            }
            default {
                throw "Unsupported ls qualifier '$char' in '$Qualifier'."
            }
        }
    }

    if ($negate) {
        throw "Qualifier '$Qualifier' ends with '^' and has nothing to negate."
    }

    [pscustomobject]$query
}

function Test-CleanCliQualifierNamePatternStart {
    param(
        [string]$Qualifier,
        [int]$Index,
        [switch]$Negate
    )

    if ($Index -eq 0 -or $Negate) {
        return $false
    }

    $char = $Qualifier[$Index]
    switch ($char) {
        '.' {
            return $true
        }
        '/' {
            return -not ($Index -eq 1 -and ($Qualifier[0] -eq '.' -or $Qualifier[0] -eq '*'))
        }
        '@' {
            return $false
        }
        { $_ -in @('m', 'a') } {
            return -not (Test-CleanCliQualifierTimeTokenStart -Qualifier $Qualifier -Index $Index)
        }
        'L' {
            return -not (Test-CleanCliQualifierSizeTokenStart -Qualifier $Qualifier -Index $Index)
        }
        { $_ -in @('o', 'O') } {
            return -not (Test-CleanCliQualifierSortTokenStart -Qualifier $Qualifier -Index $Index)
        }
        '[' {
            return $false
        }
        '^' {
            return $false
        }
        'F' {
            return $false
        }
        default {
            return $true
        }
    }
}

function Test-CleanCliQualifierTimeTokenStart {
    param(
        [string]$Qualifier,
        [int]$Index
    )

    $index = $Index + 1
    if ($index -lt $Qualifier.Length -and $Qualifier[$index] -in @('h', 'm', 's', 'd', 'w')) {
        $index++
    }

    $index -lt $Qualifier.Length -and $Qualifier[$index] -in @('-', '+')
}

function Test-CleanCliQualifierSizeTokenStart {
    param(
        [string]$Qualifier,
        [int]$Index
    )

    $index = $Index + 1
    $index -lt $Qualifier.Length -and $Qualifier[$index] -in @('-', '+')
}

function Test-CleanCliQualifierSortTokenStart {
    param(
        [string]$Qualifier,
        [int]$Index
    )

    ($Index + 1) -lt $Qualifier.Length -and $Qualifier[$Index + 1] -in @('n', 'm', 'a', 'L')
}

function Add-CleanCliQualifierType {
    param(
        [System.Collections.IDictionary]$Query,
        [string]$Type,
        [switch]$Negate
    )

    if ($Negate) {
        switch ($Type) {
            'file' { $Query.TypeFilters += 'directory'; $Query.TypeFilters += 'symlink' }
            'directory' { $Query.TypeFilters += 'file'; $Query.TypeFilters += 'symlink' }
            'symlink' { $Query.TypeFilters += 'file'; $Query.TypeFilters += 'directory' }
        }
    }
    else {
        $Query.TypeFilters += $Type
    }
    $Query.HasCriteria = $true
}

function Read-CleanCliQualifierTime {
    param(
        [string]$Qualifier,
        [int]$Index,
        [System.Collections.IDictionary]$Query,
        [switch]$Negate
    )

    $kind = $Qualifier[$Index]
    $index++
    $unit = 'd'
    $unitWasPrefixed = $false
    if ($index -lt $Qualifier.Length -and $Qualifier[$index] -in @('h', 'm', 's', 'd', 'w')) {
        $unit = [string]$Qualifier[$index]
        $unitWasPrefixed = $true
        $index++
    }
    if ($index -ge $Qualifier.Length -or $Qualifier[$index] -notin @('-', '+')) {
        throw "Qualifier '$kind' in '$Qualifier' must include '-' for within or '+' for before."
    }
    $sign = $Qualifier[$index]
    $index++
    $start = $index
    while ($index -lt $Qualifier.Length -and [char]::IsDigit($Qualifier[$index])) {
        $index++
    }
    if ($start -eq $index) {
        throw "Qualifier '$kind$sign' in '$Qualifier' must include a number."
    }
    $number = $Qualifier.Substring($start, $index - $start)

    if (-not $unitWasPrefixed -and $index -lt $Qualifier.Length -and $Qualifier[$index] -in @('h', 'm', 's', 'd', 'w')) {
        $unit = [string]$Qualifier[$index]
        $index++
    }

    $duration = ConvertTo-CleanCliDuration -Value "$number$unit"
    $within = $sign -eq '-'
    if ($Negate) { $within = -not $within }
    if ($kind -eq 'm') {
        if ($within) { $Query.ModifiedWithin = $duration } else { $Query.ModifiedBefore = $duration }
    }
    else {
        if ($within) { $Query.AccessedWithin = $duration } else { $Query.AccessedBefore = $duration }
    }
    $Query.HasCriteria = $true
    $index
}

function Read-CleanCliQualifierSize {
    param(
        [string]$Qualifier,
        [int]$Index,
        [System.Collections.IDictionary]$Query,
        [switch]$Negate
    )

    $index++
    if ($index -ge $Qualifier.Length -or $Qualifier[$index] -notin @('-', '+')) {
        throw "Qualifier 'L' in '$Qualifier' must include '-' for smaller or '+' for larger."
    }
    $sign = $Qualifier[$index]
    $index++
    $start = $index
    while ($index -lt $Qualifier.Length -and [char]::IsDigit($Qualifier[$index])) {
        $index++
    }
    if ($start -eq $index) {
        throw "Qualifier 'L$sign' in '$Qualifier' must include a number."
    }
    $unit = ''
    if ($index -lt $Qualifier.Length -and $Qualifier[$index] -in @('k', 'K', 'm', 'M', 'g', 'G')) {
        $unit = [string]$Qualifier[$index]
        $index++
    }

    $bytes = ConvertTo-CleanCliSizeBytes -Value "$($Qualifier.Substring($start, $index - $start - $unit.Length))$unit"
    $larger = $sign -eq '+'
    if ($Negate) { $larger = -not $larger }
    if ($larger) { $Query.LargerThan = $bytes } else { $Query.SmallerThan = $bytes }
    $Query.HasCriteria = $true
    $index
}

function Read-CleanCliQualifierSort {
    param(
        [string]$Qualifier,
        [int]$Index,
        [System.Collections.IDictionary]$Query
    )

    $descending = [string]$Qualifier[$Index] -ceq 'O'
    $index++
    if ($index -ge $Qualifier.Length) {
        throw "Qualifier '$($Qualifier[$Index - 1])' in '$Qualifier' must include a sort key."
    }
    switch ($Qualifier[$index]) {
        'n' { $Query.Sort = 'name' }
        'm' { $Query.Sort = 'modified' }
        'a' { $Query.Sort = 'accessed' }
        'L' { $Query.Sort = 'size' }
        default { throw "Unsupported sort qualifier '$($Qualifier[$index])' in '$Qualifier'." }
    }
    $Query.Descending = $descending
    $Query.HasCriteria = $true
    $index + 1
}

function Read-CleanCliQualifierSlice {
    param(
        [string]$Qualifier,
        [int]$Index,
        [System.Collections.IDictionary]$Query
    )

    $endIndex = $Qualifier.IndexOf(']', $Index + 1)
    if ($endIndex -lt 0) {
        throw "Qualifier slice in '$Qualifier' is missing ']'."
    }
    $body = $Qualifier.Substring($Index + 1, $endIndex - $Index - 1)
    if ($body -notmatch '^-?\d+(,-?\d+)?$') {
        throw "Qualifier slice '[$body]' must be [n] or [n,m]."
    }
    $parts = $body.Split(',')
    $Query.SliceStart = [int]$parts[0]
    $Query.SliceEnd = if ($parts.Count -gt 1) { [int]$parts[1] } else { [int]$parts[0] }
    $Query.HasCriteria = $true
    $endIndex + 1
}

function Test-CleanCliListingSymlink {
    param([System.IO.FileSystemInfo]$Item)

    [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Test-CleanCliListingEmptyDirectory {
    param([System.IO.FileSystemInfo]$Item)

    if (-not $Item.PSIsContainer) {
        return $false
    }

    -not [bool](Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}


function Sort-CleanCliListingItem {
    param(
        [object[]]$Items,
        [Parameter(Mandatory)]
        [object]$Query
    )

    $result = @($Items)
    if ($Query.Sort) {
        # Use string property names where possible — Sort-Object uses .NET reflection directly,
        # avoiding per-item scriptblock invocation overhead of the scriptblock form.
        # 'size' needs a scriptblock because directories have no Length.
        if ($Query.Sort -eq 'size') {
            $result = @($result | Sort-Object -Property { if ($_.PSIsContainer) { -1 } else { $_.Length } } -Descending:([bool]$Query.Descending))
        } else {
            $property = switch ($Query.Sort) {
                'modified' { 'LastWriteTime' }
                'accessed' { 'LastAccessTime' }
                default    { 'Name' }
            }
            $result = @($result | Sort-Object -Property $property -Descending:([bool]$Query.Descending))
        }
    }
    elseif ($Query.Descending) {
        $result = @($result | Sort-Object -Property Name -Descending)
    }

    if ($null -ne $Query.SliceStart) {
        $count = $result.Count
        if ($count -eq 0) { return @() }

        $start = [int]$Query.SliceStart
        $end = [int]$Query.SliceEnd
        if ($start -lt 0) { $start = $count + $start + 1 }
        if ($end -lt 0) { $end = $count + $end + 1 }
        $start = [math]::Max(1, $start)
        $end = [math]::Min($count, $end)
        if ($start -gt $end) { return @() }

        $result = @($result[($start - 1)..($end - 1)])
    }

    $result
}

function Invoke-CleanCliListingQuery {
    param(
        [object[]]$Items,
        [Parameter(Mandatory)]
        [object]$Query
    )

    if (-not $Query.HasCriteria) {
        return @($Items)
    }

    $modifiedWithinCutoff  = if ($Query.ModifiedWithin)  { [DateTime]::Now - $Query.ModifiedWithin  } else { $null }
    $modifiedBeforeCutoff  = if ($Query.ModifiedBefore)  { [DateTime]::Now - $Query.ModifiedBefore  } else { $null }
    $accessedWithinCutoff  = if ($Query.AccessedWithin)  { [DateTime]::Now - $Query.AccessedWithin  } else { $null }
    $accessedBeforeCutoff  = if ($Query.AccessedBefore)  { [DateTime]::Now - $Query.AccessedBefore  } else { $null }

    $filtered = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
    foreach ($item in $Items) {
        if ($Query.TypeFilters.Count -gt 0) {
            $matchesType = $false
            foreach ($type in $Query.TypeFilters) {
                if ($type -eq 'file'      -and -not $item.PSIsContainer -and -not (Test-CleanCliListingSymlink -Item $item)) { $matchesType = $true }
                if ($type -eq 'directory' -and $item.PSIsContainer) { $matchesType = $true }
                if ($type -eq 'symlink'   -and (Test-CleanCliListingSymlink -Item $item)) { $matchesType = $true }
            }
            if (-not $matchesType) { continue }
        }

        if ($Query.EmptyFilters.Count -gt 0) {
            $isEmpty = Test-CleanCliListingEmptyDirectory -Item $item
            if ($isEmpty -notin $Query.EmptyFilters) { continue }
        }

        if ($modifiedWithinCutoff  -and $item.LastWriteTime  -lt $modifiedWithinCutoff)  { continue }
        if ($modifiedBeforeCutoff  -and $item.LastWriteTime  -gt $modifiedBeforeCutoff)  { continue }
        if ($accessedWithinCutoff  -and $item.LastAccessTime -lt $accessedWithinCutoff)  { continue }
        if ($accessedBeforeCutoff  -and $item.LastAccessTime -gt $accessedBeforeCutoff)  { continue }
        if ($null -ne $Query.LargerThan  -and ($item.PSIsContainer -or $item.Length -le $Query.LargerThan))  { continue }
        if ($null -ne $Query.SmallerThan -and ($item.PSIsContainer -or $item.Length -ge $Query.SmallerThan)) { continue }
        if ($Query.NameLike       -and $item.Name -notlike $Query.NameLike) { continue }
        if ($Query.Extensions.Count -gt 0 -and ([System.IO.Path]::GetExtension($item.Name).ToLowerInvariant()) -notin $Query.Extensions) { continue }

        $filtered.Add($item)
    }

    Sort-CleanCliListingItem -Items $filtered -Query $Query
}
