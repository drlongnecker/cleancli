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

## Prompt Display

CleanCli renders Powerline-style segments with bridge separators. The separator foreground uses the previous segment background and the separator background uses the next segment background, so path and git blocks connect cleanly when the terminal font supports Powerline glyphs.

Set `PathDisplayMode` to `full`, `compact`, or `auto`. `auto` keeps short paths unchanged and compacts long paths to root plus useful leaf context, for example `~\AppData\...\blob_storage\09064e10...`.

Set `PromptLayout` to `single`, `two-line`, or `auto`. `single` keeps the command on the same line. `two-line` moves command entry to a new prompt line. `auto` switches to two-line layout when the visible prompt text is long.

## Key Bindings

- `Tab`: menu completion
- `RightArrow`: accept inline prediction
- `Ctrl+r`: reverse history search

Inline predictions use PSReadLine history only. No plugin, package install, schema download, icon download, or remote metadata check is used.

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
Measure-CleanCliStartup
```

`Get-CleanCliStatus` includes `LastGitDurationMilliseconds` so slow repositories can be identified from the last bounded git call. `LastGit` includes the repo root, git dir, cache key, exact git arguments, suppression count and threshold, data source (`none`, `branch-only`, `full`, `cached`, `last-successful`, or `suppressed`), and the parsed status counters (`Added`, `Modified`, `Deleted`, `Moved`, `Unmerged`, `Untracked`, and `StatusSummary`).

Run tests:

```powershell
pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Script '.\tests\CleanCli.Tests.ps1'"
```
