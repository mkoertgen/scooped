# GitHub provider using gh CLI
# Cross-platform compatible

function Test-GitHubCLI {
    $ghCommand = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        Get-Command gh.exe -ErrorAction SilentlyContinue
    } else {
        Get-Command gh -ErrorAction SilentlyContinue
    }

    if (-not $ghCommand) {
        throw "GitHub CLI (gh) not found. Install: https://cli.github.com/"
    }

    # Check authentication
    $authStatus = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI not authenticated. Run: gh auth login"
    }
}

function Get-CurrentRepo {
    # Check if we're in a git repository
    $gitDir = & git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    # Get remote URL
    $remoteUrl = & git config --get remote.origin.url 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) {
        return $null
    }

    # Parse owner/repo from URL
    # Supports: https://github.com/owner/repo.git or git@github.com:owner/repo.git
    if ($remoteUrl -match 'github\.com[:/]([^/]+)/(.+?)(\.git)?$') {
        return "$($matches[1])/$($matches[2])"
    }

    return $null
}

function Get-BotPRs {
    param(
        [Parameter(Mandatory)]
        [string]$Repo,

        [Parameter(Mandatory)]
        [string[]]$Bots,

        [ValidateSet('open', 'closed', 'all')]
        [string]$Status = 'open'
    )

    Test-GitHubCLI

    # Build bot user filter from config
    $config = Get-Config
    $botUsers = @()
    foreach ($botName in $Bots) {
        $botConfig = $config.bots.$botName
        if ($botConfig -and $botConfig.enabled) {
            $botUsers += $botConfig.users
        }
    }

    if ($botUsers.Count -eq 0) {
        Write-Warning "No enabled bots found in configuration"
        return @()
    }

    # Query GitHub for PRs
    $stateFilter = switch ($Status) {
        'open' { 'open' }
        'closed' { 'closed' }
        'all' { 'all' }
    }

    try {
        # Get all PRs with JSON output
        $json = & gh pr list --repo $Repo --state $stateFilter --json number,title,author,state,mergeable,statusCheckRollup,headRefName --limit 100

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to list PRs: $json"
        }

        $allPRs = $json | ConvertFrom-Json

        # Filter to bot PRs only
        $botPRs = $allPRs | Where-Object {
            $author = $_.author.login
            $botUsers -contains $author
        }

        # Transform to our format
        $result = $botPRs | ForEach-Object {
            $mergeable = $_.mergeable -eq 'MERGEABLE'
            $mergeableReason = if (-not $mergeable) {
                switch ($_.mergeable) {
                    'CONFLICTING' { 'Conflicts with base branch' }
                    'UNKNOWN' { 'Mergeable status unknown' }
                    default { $_.mergeable }
                }
            } else {
                $null
            }

            # Determine overall CI status
            $ciStatus = 'UNKNOWN'
            if ($_.statusCheckRollup) {
                $ciStatus = $_.statusCheckRollup.state
            }

            [PSCustomObject]@{
                number = $_.number
                title = $_.title
                author = $_.author.login
                state = $_.state
                branch = $_.headRefName
                mergeable = $mergeable
                mergeableReason = $mergeableReason
                status = $ciStatus
            }
        }

        return $result

    } catch {
        Write-Error "Failed to get bot PRs: $_"
        return @()
    }
}

function Merge-PR {
    param(
        [Parameter(Mandatory)]
        [string]$Repo,

        [Parameter(Mandatory)]
        [int]$Number,

        [ValidateSet('rebase', 'squash', 'merge')]
        [string]$Strategy = 'rebase',

        [switch]$DeleteBranch
    )

    Test-GitHubCLI

    $strategyFlag = switch ($Strategy) {
        'rebase' { '--rebase' }
        'squash' { '--squash' }
        'merge' { '--merge' }
    }

    $args = @('pr', 'merge', $Number, '--repo', $Repo, $strategyFlag)

    if ($DeleteBranch) {
        $args += '--delete-branch'
    }

    try {
        $output = & gh @args 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "gh pr merge failed: $output"
        }

        Write-Verbose "Merged PR #$Number with strategy $Strategy"

    } catch {
        throw "Failed to merge PR #${Number}: $_"
    }
}

Export-ModuleMember -Function Test-GitHubCLI, Get-CurrentRepo, Get-BotPRs, Merge-PR
