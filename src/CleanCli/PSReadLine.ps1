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

function Set-CleanCliPSReadLine {
    if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
        return
    }

    Save-CleanCliKeyHandler -Key Tab
    Save-CleanCliKeyHandler -Key RightArrow
    Save-CleanCliKeyHandler -Key Ctrl+r

    try {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -ErrorAction Stop
    }
    catch {
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
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

    if ($script:CleanCliState.OriginalContinuationPrompt) {
        Set-PSReadLineOption -ContinuationPrompt $script:CleanCliState.OriginalContinuationPrompt
    }
    if ($script:CleanCliState.OriginalPromptText) {
        Set-PSReadLineOption -PromptText $script:CleanCliState.OriginalPromptText
    }
}
