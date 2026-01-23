# git-merge-bots - Automatically merge bot PRs (Dependabot, Renovate, etc.)
# Cross-platform PowerShell module (PS 5.1+ and pwsh compatible)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Dot-source library files
. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\bots.ps1"
. "$PSScriptRoot\lib\providers\github.ps1"

function Show-Help {
    $help = @"

git-merge-bots - Automatically merge bot PRs

USAGE:
    git-merge-bots <command> [options]

COMMANDS:
    list            List bot PRs in current or specified repo
    merge           Merge bot PRs
    config          Show or edit configuration
    help            Show this help

LIST OPTIONS:
    -Repo <owner/repo>      Specific repository (default: current directory)
    -Bots <bot1,bot2>       Filter by bot names (default: all configured bots)
    -Status <status>        Filter by PR status: open, closed, all (default: open)

MERGE OPTIONS:
    -Repo <owner/repo>      Specific repository (default: current directory)
    -Bots <bot1,bot2>       Filter by bot names (default: all configured bots)
    -Strategy <strategy>    Merge strategy: rebase, squash, merge (default: rebase)
    -DryRun                 Show what would be merged without doing it
    -Force                  Skip safety checks (conflicts, CI status)

CONFIG OPTIONS:
    -Show                   Show current configuration
    -Edit                   Open config file in editor
    -Reset                  Reset to default configuration

EXAMPLES:
    # List all bot PRs in current repo
    git-merge-bots list

    # List only Dependabot PRs
    git-merge-bots list -Bots dependabot

    # Dry-run merge all bot PRs
    git-merge-bots merge --dry-run

    # Merge only Renovate PRs with squash strategy
    git-merge-bots merge -Bots renovate -Strategy squash

    # Merge PRs in specific repo
    git-merge-bots merge -Repo owner/repo

    # Show configuration
    git-merge-bots config -Show

CONFIGURATION:
    Config file: ~/.git-merge-bots.json

    Default bots: dependabot, renovate
    Default strategy: rebase
    Default auto-delete-branch: true

For more information, see README.md

"@
    Write-Host $help
}

function Invoke-ListBotPRs {
    param(
        [string]$Repo,
        [string[]]$Bots,
        [ValidateSet('open', 'closed', 'all')]
        [string]$Status = 'open'
    )

    $config = Get-Config
    if (-not $Bots) {
        $Bots = $config.bots.PSObject.Properties.Name
    }

    # Detect current repo if not specified
    if (-not $Repo) {
        $Repo = Get-CurrentRepo
        if (-not $Repo) {
            Write-Host "Skipped: Not a GitHub repository" -ForegroundColor DarkGray
            return
        }
    }

    Write-Host "Listing bot PRs in $Repo..." -ForegroundColor Cyan
    Write-Host "Bots: $($Bots -join ', ')" -ForegroundColor Gray
    Write-Host ""

    $prs = Get-BotPRs -Repo $Repo -Bots $Bots -Status $Status

    if (-not $prs -or @($prs).Count -eq 0) {
        Write-Host "No bot PRs found." -ForegroundColor Yellow
        return
    }

    foreach ($pr in $prs) {
        $botInfo = Get-BotInfo -Author $pr.author
        $statusColor = if ($pr.mergeable) { 'Green' } else { 'Red' }

        Write-Host "#$($pr.number) " -NoNewline -ForegroundColor White
        Write-Host "[$($botInfo.name)]" -NoNewline -ForegroundColor Magenta
        Write-Host " $($pr.title)" -ForegroundColor White
        Write-Host "  Author: $($pr.author)" -ForegroundColor Gray
        Write-Host "  Status: " -NoNewline -ForegroundColor Gray
        Write-Host $pr.status -ForegroundColor $statusColor
        if (-not $pr.mergeable) {
            Write-Host "  ⚠ Not mergeable: $($pr.mergeableReason)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "Total: $(@($prs).Count) bot PRs" -ForegroundColor Cyan
}

function Invoke-MergeBotPRs {
    param(
        [string]$Repo,
        [string[]]$Bots,
        [ValidateSet('rebase', 'squash', 'merge')]
        [string]$Strategy,
        [switch]$DryRun,
        [switch]$Force
    )

    $config = Get-Config

    if (-not $Bots) {
        $Bots = $config.bots.PSObject.Properties.Name
    }

    if (-not $Strategy) {
        $Strategy = $config.mergeStrategy
    }

    # Detect current repo if not specified
    if (-not $Repo) {
        $Repo = Get-CurrentRepo
        if (-not $Repo) {
            Write-Host "Skipped: Not a GitHub repository" -ForegroundColor DarkGray
            return
        }
    }

    Write-Host "Merging bot PRs in $Repo..." -ForegroundColor Cyan
    Write-Host "Bots: $($Bots -join ', ')" -ForegroundColor Gray
    Write-Host "Strategy: $Strategy" -ForegroundColor Gray
    if ($DryRun) {
        Write-Host "Mode: DRY RUN (no actual merges)" -ForegroundColor Yellow
    }
    Write-Host ""

    $prs = Get-BotPRs -Repo $Repo -Bots $Bots -Status 'open'

    if (-not $prs -or @($prs).Count -eq 0) {
        Write-Host "No bot PRs to merge." -ForegroundColor Yellow
        return
    }

    $merged = 0
    $skipped = 0
    $failed = 0

    foreach ($pr in $prs) {
        $botInfo = Get-BotInfo -Author $pr.author
        Write-Host "Processing #$($pr.number) [$($botInfo.name)] $($pr.title)" -ForegroundColor White

        # Safety checks (skip if -Force)
        if (-not $Force) {
            if (-not $pr.mergeable) {
                Write-Host "  ⚠ Skipped: $($pr.mergeableReason)" -ForegroundColor Yellow
                $skipped++
                continue
            }

            if ($pr.status -ne 'SUCCESS') {
                Write-Host "  ⚠ Skipped: CI checks not passed ($($pr.status))" -ForegroundColor Yellow
                $skipped++
                continue
            }
        }

        if ($DryRun) {
            Write-Host "  ✓ Would merge with strategy: $Strategy" -ForegroundColor Green
            $merged++
        } else {
            try {
                Merge-PR -Repo $Repo -Number $pr.number -Strategy $Strategy -DeleteBranch:$config.deleteBranch
                Write-Host "  ✓ Merged successfully" -ForegroundColor Green
                $merged++
            } catch {
                Write-Host "  ✗ Failed: $_" -ForegroundColor Red
                $failed++
            }
        }
        Write-Host ""
    }

    # Summary
    Write-Host "─────────────────────────────────" -ForegroundColor Gray
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Merged: $merged" -ForegroundColor Green
    if ($skipped -gt 0) {
        Write-Host "  Skipped: $skipped" -ForegroundColor Yellow
    }
    if ($failed -gt 0) {
        Write-Host "  Failed: $failed" -ForegroundColor Red
    }
}

function Invoke-ConfigCommand {
    param(
        [switch]$Show,
        [switch]$Edit,
        [switch]$Reset
    )

    if ($Reset) {
        $confirm = Read-Host "Reset configuration to defaults? (y/N)"
        if ($confirm -eq 'y') {
            Reset-Config
            Write-Host "Configuration reset to defaults." -ForegroundColor Green
        }
        return
    }

    if ($Edit) {
        $configPath = Get-ConfigPath
        if (Get-Command code -ErrorAction SilentlyContinue) {
            & code $configPath
        } elseif (Get-Command notepad -ErrorAction SilentlyContinue) {
            & notepad $configPath
        } else {
            Write-Host "Config file: $configPath"
            Write-Host "Please open it manually in your editor."
        }
        return
    }

    # Default: Show config
    Show-Config
}

function Invoke-GitMergeBots {
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$RemainingArgs
    )

    switch ($Command) {
        'list' {
            $params = @{}
            if ($RemainingArgs) {
                for ($i = 0; $i -lt @($RemainingArgs).Count; $i++) {
                    switch ($RemainingArgs[$i]) {
                        '-Repo' { $params.Repo = $RemainingArgs[++$i] }
                        '-Bots' { $params.Bots = $RemainingArgs[++$i] -split ',' }
                        '-Status' { $params.Status = $RemainingArgs[++$i] }
                    }
                }
            }
            Invoke-ListBotPRs @params
        }
        'merge' {
            $params = @{}
            if ($RemainingArgs) {
                for ($i = 0; $i -lt @($RemainingArgs).Count; $i++) {
                    switch ($RemainingArgs[$i]) {
                        '-Repo' { $params.Repo = $RemainingArgs[++$i] }
                        '-Bots' { $params.Bots = $RemainingArgs[++$i] -split ',' }
                        '-Strategy' { $params.Strategy = $RemainingArgs[++$i] }
                        { $_ -in '--dry-run', '-DryRun' } { $params.DryRun = $true }
                        { $_ -in '--force', '-Force' } { $params.Force = $true }
                    }
                }
            }
            Invoke-MergeBotPRs @params
        }
        'config' {
            $params = @{}
            if ($RemainingArgs) {
                for ($i = 0; $i -lt @($RemainingArgs).Count; $i++) {
                    switch ($RemainingArgs[$i]) {
                        { $_ -in '--show', '-Show' } { $params.Show = $true }
                        { $_ -in '--edit', '-Edit' } { $params.Edit = $true }
                        { $_ -in '--reset', '-Reset' } { $params.Reset = $true }
                    }
                }
            }
            Invoke-ConfigCommand @params
        }
        'help' {
            Show-Help
        }
        default {
            if ($Command) {
                Write-Host "Unknown command: $Command" -ForegroundColor Red
                Write-Host ""
            }
            Show-Help
        }
    }
}

Export-ModuleMember -Function Invoke-GitMergeBots
