# CleanCLI

CleanCLI is an offline native PowerShell prompt and PSReadLine setup for Windows PowerShell sessions.

## Background

As a long time user of Oh My Zsh and Oh My Posh, I wanted to figure out something faster for my machine. I noticed a few challenges:

1. the rich theme and 'update' library pinged the internet and would result in a delay (lack of offlining/timeout support)
2. large git repos seemed to take _forever_ to iterate if there were large file structure changes every single command line prompt, even if no git changes were made (lack of stateful caching)
3. large non-git directories also seemed to take a while to iterate due to it looking for git assets (not failing fast)

As I bounce between different machines, I also needed something I could make portable as part of my profile, but detect which machine I was on to provide the right environment.

Originally, I'd tried shoving everything in my Profile and sharing that around, but it became a complicated mess of if/then's rather than the modular system I'd hoped to use.  _Part of that wasn't helped by my need to save everything and having random helper functions in there from 2010._

So the goal is to create a clean CLI that feels native with enough tuning and customization and portability.

## Install

Use `settings\Microsoft.PowerShell_profile.ps1` as the PowerShell profile content, or dot-source it from your existing profile.

The profile imports `src\CleanCli\CleanCli.psd1` and runs `Enable-CleanCli` only when profile loading is enabled. Commands launched with `pwsh -NoProfile` do not load CleanCli.

## Disable

Disable for one process:

```powershell
$env:CLEANCLI_DISABLE = '1'
pwsh
```

Force loading in a non-interactive host:

```powershell
$env:CLEANCLI_INTERACTIVE_ONLY = '0'
```

Use plain ASCII prompt symbols:

```powershell
$env:CLEANCLI_ASCII = '1'
```

## Configuration

CleanCli looks for `CleanCli.config.psd1` from the current directory upward when it initializes.

Example:

```powershell
@{
    GitTimeoutMilliseconds = 1000
    GitCacheMilliseconds = 750
    GitSlowSuppressionTimeouts = 2
    GitUntrackedMode = 'normal'
    GitIgnoreSubmodules = 'none'
    GitStatusMode = 'full'
    GitDivergenceMode = 'none'
    PathDisplayMode = 'auto'
    PromptLayout = 'single'
    IconMode = 'disabled'
    CommandDurationThresholdMilliseconds = 2000
    RightPrompt = $false
    PromptSeparator = 'auto'
    PathSymbol = 'auto'
    GitSymbol = 'auto'
    DirtySymbol = 'auto'
    AdminSymbol = 'auto'
    TimeSymbol = 'auto'
    AdminForeground = 'Yellow'
    AdminBackground = 'Black'
    PathForeground = 'White'
    PathBackground = 'Magenta'
    GitForeground = 'Black'
    GitBackground = 'Green'
    TimeForeground = 'Black'
    TimeBackground = 'Yellow'
    KeyBindingPreset = 'zsh'
    EnableInCodex = $true
    EnableInVSCode = $true
    EnableInWindowsTerminal = $true
    EnableInPlainConsole = $true
    AsciiMode = $false
    TransientPrompt = $false
}
```

Runtime options:

```powershell
Get-CleanCliOption
Get-CleanCliOption -Name GitTimeoutMilliseconds
Set-CleanCliOption -Name AsciiMode -Value $true
```

`Set-CleanCliOption` writes the active `CleanCli.config.psd1`. If no project config is found, CleanCli writes to `Documents\PowerShell\CleanCli.config.psd1`. Set `CLEANCLI_CONFIG_PATH` to force a specific config file path.

Environment variables still override config for existing compatibility:

- `CLEANCLI_ASCII=1`
- `CLEANCLI_TRANSIENT=1`
- `CLEANCLI_NERD_FONT=1` to force native Nerd Font icon mode, or `CLEANCLI_NERD_FONT=0` to force Terminal-Icons compatibility mode when selected

## Machine Profiles

CleanCli can load a synced `CleanCli.profiles.psd1` file from `Documents\PowerShell` so the same module and profile can be copied across machines while each machine keeps the right local behavior.

Load order:

```text
defaults
-> CleanCli.profiles.psd1 Master
-> matched machine profile
-> CleanCli.config.psd1 project or user config
-> environment variables
```

Example:

```powershell
@{
    Master = @{
        IconMode = 'native'
        KeyBindingPreset = 'zsh'
    }

    Identifiers = @{
        'JOYEUSE.david' = 'desktop'
        'KATANA.david' = 'work-laptop'
        'SRV1.david' = 'vm'
        'SRV2.david' = 'vm'
    }

    Profiles = @{
        desktop = @{
            RightPrompt = $true
        }
        'work-laptop' = @{
            GitStatusMode = 'async'
        }
        vm = @{
            IconMode = 'ascii'
            GitStatusMode = 'branch'
        }
    }
}
```

CleanCli detects the current machine as `<COMPUTERNAME>.<username>`. If that identifier is not mapped during interactive profile load, CleanCli asks whether to set up the machine. The prompt is skipped for non-interactive shells, disabled hosts, and when `CLEANCLI_PROFILES_PROMPT=0` is set.

Profile commands:

```powershell
Get-CleanCliProfile
New-CleanCliMachineProfile -ProfileName desktop
New-CleanCliMachineProfile -ProfileName vm -Force
Set-CleanCliMachineProfile -ProfileName work-laptop
```

`Get-CleanCliProfile` shows the detected identifier, mapped profile, master settings, profile settings, active config path, and final merged settings. Set `CLEANCLI_PROFILES_PATH` to force a specific profiles file path.

## Prompt Display

CleanCli renders Powerline-style segments with bridge separators. The separator foreground uses the previous segment background and the separator background uses the next segment background, so path and git blocks connect cleanly when the terminal font supports Powerline glyphs.

Set `PathDisplayMode` to `full`, `compact`, or `auto`. `auto` keeps short paths unchanged and compacts long paths to root plus useful leaf context, for example `~\AppData\...\blob_storage\09064e10...`.

Set `PromptLayout` to `single`, `two-line`, or `auto`. `single` keeps the command on the same line. `two-line` moves command entry to a new prompt line. `auto` switches to two-line layout when the visible prompt text is long.

Set `CommandDurationThresholdMilliseconds` to show a duration segment after commands that run at or above the threshold. The default is 2000 milliseconds.

Set `TransientPrompt = $true` to ask PSReadLine to rewrite previous prompts to the compact prompt marker when supported by the host. CleanCli preserves and restores the original PSReadLine prompt settings on disable.

Set `RightPrompt = $true` to render git and command duration segments on the right side of ANSI-capable terminals. CleanCli falls back to the normal left prompt when color is disabled or cursor positioning is unavailable.

Set prompt symbol options such as `PathSymbol`, `GitSymbol`, `DirtySymbol`, `AdminSymbol`, `TimeSymbol`, and `PromptSeparator` to override built-in glyphs without downloading themes. Leave them as `auto` to use Powerline glyphs or ASCII fallbacks based on `AsciiMode`.

Set segment color options such as `PathForeground`, `PathBackground`, `GitForeground`, `GitBackground`, `TimeForeground`, `TimeBackground`, `AdminForeground`, and `AdminBackground` to one of `Black`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`, `DarkGray`, or `Default`.

## Directory Icons

CleanCli can render optional file and folder icons for directory listings without downloading themes or metadata. The default `IconMode = 'disabled'` keeps normal `Get-ChildItem` output.

Use `Get-CleanCliChildItem` for icon-aware directory listings. When `IconMode` is enabled, the profile also routes `ls` and `dir` through `Get-CleanCliChildItem`. Set `IconMode` to `native` for CleanCli's offline glyph map, `terminal-icons` to use the installed `Terminal-Icons` module as a compatibility fallback, or `ascii` for `[D]` and `[F]` markers. If `IconMode = 'native'` and ASCII mode is enabled, CleanCli uses ASCII-safe icons.

The bundled profile does not import `Terminal-Icons` at startup. When `IconMode = 'terminal-icons'`, CleanCli uses native glyphs if Nerd Font support is detected, then falls back to lazy `Terminal-Icons` import only when needed. CleanCli checks `CLEANCLI_NERD_FONT` first and can also detect common Windows Terminal Nerd Font settings such as CaskaydiaCove Nerd Font.

CleanCli native icons avoid known legacy Nerd Font codepoints from old Terminal-Icons `nf-mdi-*` mappings that can render as invalid symbols in current fonts.

## Key Bindings

- `Tab`: menu completion
- `RightArrow`: accept inline prediction
- `Ctrl+r`: reverse history search
- `UpArrow` / `DownArrow`: substring history search in the default `zsh` preset

Inline predictions use PSReadLine history only. No plugin, package install, schema download, icon download, or remote metadata check is used.

Set `KeyBindingPreset` to `zsh`, `powershell`, or `minimal`. `zsh` enables menu completion, substring history search, reverse search, and right-arrow suggestion acceptance. `powershell` leaves PSReadLine navigation bindings alone. `minimal` only tunes Tab completion.

Use `Set-CleanCliLocation` for directory jumping. It records visited directories in a persistent local history file and accepts fuzzy history matches after a location has been visited. Use `Get-CleanCliLocationHistory` to inspect that history.

The old profile helpers now live as module commands: `Show-CleanCliGitLog` for the decorated git log and `Open-CleanCliExplorer` for opening Explorer at a path.

## Git Behavior

CleanCLI walks parent directories looking for `.git`. Outside a repository it returns immediately and does not start `git.exe`.

Inside a repository it parses `.git\HEAD` directly for the branch. Dirty, staged, unstaged, and untracked counts come from a timeout-bounded local `git --no-optional-locks -c core.quotepath=false -c color.status=false status --porcelain=v1 --untracked-files=normal --ignore-submodules=none` call. This lets git apply its index and ignore rules instead of making CleanCli crawl the tree itself.

Dirty prompts render an Oh My Posh-style status breakdown instead of one combined count. The default order is untracked `?`, added `+`, modified `~`, deleted `-`, moved `>`, and unmerged `x`, for example `* ?3 +1 ~4 -2`.

Set `GitUntrackedMode` to `no`, `normal`, or `all` to control `--untracked-files`. Set `GitIgnoreSubmodules` to `none`, `untracked`, `dirty`, or `all` to control `--ignore-submodules`.

Set `GitStatusMode` to `full`, `branch`, or `async`. `branch` reads only `.git\HEAD` and never invokes `git status`. `async` renders branch-only information immediately, then refreshes cached file counts in the background for the next prompt.

Remote ahead/behind counts stay out of the default path. Set `GitDivergenceMode = 'local'` to add `--branch` and parse ahead/behind from local porcelain output.

If git is slow, the prompt degrades to branch-only information and records the slow call in `Get-CleanCliStatus`. After repeated timeout events for the same repository, CleanCli suppresses full git status and keeps using branch-only information.

## Diagnostics

```powershell
Import-Module .\src\CleanCli\CleanCli.psd1 -Force
Enable-CleanCli
Get-CleanCliStatus
Get-CleanCliProfile
Get-CleanCliIconDiagnostics
Measure-CleanCliStartup
Measure-CleanCliStartup -Iterations 5
```

`Get-CleanCliStatus` includes `LastGitDurationMilliseconds` so slow repositories can be identified from the last bounded git call. `LastGit` includes the repo root, git dir, cache key, exact git arguments, suppression count and threshold, data source (`none`, `branch-only`, `full`, `cached`, `last-successful`, or `suppressed`), and the parsed status counters (`Added`, `Modified`, `Deleted`, `Moved`, `Unmerged`, `Untracked`, and `StatusSummary`).

`Get-CleanCliIconDiagnostics` reports the configured and effective icon mode, Nerd Font detection, Terminal-Icons availability and load state, and the current `ls` and `dir` alias routing.

`Measure-CleanCliStartup` reports separate timings for the no-profile baseline, CleanCli import, CleanCli enable, Terminal-Icons import, CleanCli plus Terminal-Icons, normal profile load, and forced profile load. Use `-Iterations` to add min/average/max statistics for each layer and reduce noise from one-off Windows process startup variance.

`Get-CleanCliStatus` also reports `HostName`, `LoadStatus`, `LoadReason`, `ProfileIdentifier`, `ProfileName`, `ProfileMapped`, and `ProfilesPath` so profile diagnostics can explain whether CleanCli loaded, skipped initialization, or matched a machine profile. Set `EnableInCodex`, `EnableInVSCode`, `EnableInWindowsTerminal`, or `EnableInPlainConsole` to `$false` to skip prompt initialization for that host.

Install or update the module without network access:

```powershell
Import-Module .\src\CleanCli\CleanCli.psd1 -Force
Install-CleanCli
```

Run tests:

```powershell
pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script '.\tests\CleanCli.Tests.ps1'"
```
