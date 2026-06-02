function Save-CleanCliKeyHandler {
    param([string]$Key)

    if ($script:CleanCliState.OriginalKeyHandlers.ContainsKey($Key)) {
        return
    }

    $handler = Get-PSReadLineKeyHandler -Key $Key -ErrorAction SilentlyContinue
    if ($handler) {
        $script:CleanCliState.OriginalKeyHandlers[$Key] = $handler.Function
    }
}

function Save-CleanCliPSReadLineOptions {
    if ($script:CleanCliState.OriginalPSReadLineOptionsCaptured) {
        return
    }

    $options = Get-PSReadLineOption -ErrorAction SilentlyContinue
    if (-not $options) {
        return
    }

    $script:CleanCliState.OriginalContinuationPrompt = $options.ContinuationPrompt
    $script:CleanCliState.OriginalPromptText = $options.PromptText
    $script:CleanCliState.OriginalExtraPromptLineCount = $options.ExtraPromptLineCount
    $script:CleanCliState.OriginalPSReadLineOptionsCaptured = $true
}

function Get-CleanCliKeyBindingsForPreset {
    param([string]$Preset = (Get-CleanCliOption -Name KeyBindingPreset))

    switch ($Preset) {
        'powershell' { return @() }
        'minimal' {
            return @(
                [pscustomobject]@{ Key = 'Tab'; Function = 'MenuComplete' }
            )
        }
        default {
            return @(
                [pscustomobject]@{ Key = 'Tab'; Function = 'MenuComplete' }
                [pscustomobject]@{ Key = 'RightArrow'; Function = 'AcceptSuggestion' }
                [pscustomobject]@{ Key = 'Ctrl+r'; Function = 'ReverseSearchHistory' }
                [pscustomobject]@{ Key = 'UpArrow'; Function = 'HistorySearchBackward' }
                [pscustomobject]@{ Key = 'DownArrow'; Function = 'HistorySearchForward' }
            )
        }
    }
}

function Set-CleanCliPSReadLine {
    if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
        return
    }

    Save-CleanCliPSReadLineOptions
    $bindings = Get-CleanCliKeyBindingsForPreset
    foreach ($binding in $bindings) {
        Save-CleanCliKeyHandler -Key $binding.Key
    }

    try {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -CompletionQueryItems 50 -ErrorAction Stop
    }
    catch {
    }

    $options = Get-CleanCliOption
    if ($options.TransientPrompt) {
        $symbols = Get-CleanCliSymbols
        Set-PSReadLineOption -PromptText "$($symbols.Separator) " -ExtraPromptLineCount 0
    }

    foreach ($binding in $bindings) {
        Set-PSReadLineKeyHandler -Key $binding.Key -Function $binding.Function
    }
}

function Restore-CleanCliPSReadLine {
    if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
        return
    }

    foreach ($key in $script:CleanCliState.OriginalKeyHandlers.Keys) {
        $functionName = $script:CleanCliState.OriginalKeyHandlers[$key]
        if ($functionName) {
            Set-PSReadLineKeyHandler -Key $key -Function $functionName
        }
    }

    if ($script:CleanCliState.OriginalPSReadLineOptionsCaptured) {
        Set-PSReadLineOption -ContinuationPrompt $script:CleanCliState.OriginalContinuationPrompt

        $promptText = $script:CleanCliState.OriginalPromptText
        if ($null -eq $promptText) {
            $promptText = ''
        }
        Set-PSReadLineOption -PromptText $promptText

        if ($null -ne $script:CleanCliState.OriginalExtraPromptLineCount) {
            Set-PSReadLineOption -ExtraPromptLineCount $script:CleanCliState.OriginalExtraPromptLineCount
        }

        $script:CleanCliState.OriginalContinuationPrompt = $null
        $script:CleanCliState.OriginalPromptText = $null
        $script:CleanCliState.OriginalExtraPromptLineCount = $null
        $script:CleanCliState.OriginalPSReadLineOptionsCaptured = $false
    }
}
