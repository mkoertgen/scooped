# GitHub provider using gh CLI
# Cross-platform compatible

function Test-GitHubCLI {
  # PS 5.1 doesn't have $IsWindows
  $isWin = (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) -or $IsWindows
  $ghCommand = if ($isWin) {
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

  if (-not $botUsers -or @($botUsers).Count -eq 0) {
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
    $json = & gh pr list --repo $Repo --state $stateFilter --json "number,title,author,state,mergeable,statusCheckRollup,headRefName" --limit 100

    if ($LASTEXITCODE -ne 0) {
      throw "Failed to list PRs: $json"
    }

    $allPRs = $json | ConvertFrom-Json

    # Filter to bot PRs only
    # Support both exact match and flexible matching for app/* prefixes
    $botPRs = $allPRs | Where-Object {
      $author = $_.author.login
      # Exact match
      if ($botUsers -contains $author) {
        return $true
      }
      # Flexible match: "app/dependabot" matches "dependabot[bot]"
      foreach ($botUser in $botUsers) {
        $botName = $botUser -replace '\[bot\]$', '' -replace '-preview$', ''
        if ($author -match "^app/$botName" -or $author -match "^$botName") {
          return $true
        }
      }
      return $false
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
      if ($_.PSObject.Properties['statusCheckRollup'] -and $_.statusCheckRollup) {
        if ($_.statusCheckRollup.PSObject.Properties['state']) {
          $ciStatus = $_.statusCheckRollup.state
        }
      }

      [PSCustomObject]@{
        number          = $_.number
        title           = $_.title
        author          = $_.author.login
        state           = $_.state
        branch          = $_.headRefName
        mergeable       = $mergeable
        mergeableReason = $mergeableReason
        status          = $ciStatus
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

function Update-PRBranch {
  param(
    [Parameter(Mandatory)]
    [string]$Repo,

    [Parameter(Mandatory)]
    [int]$Number
  )

  Test-GitHubCLI

  try {
    # Use gh api to update branch (rebase on base branch)
    $output = & gh api "repos/$Repo/pulls/$Number/update-branch" -X PUT 2>&1

    if ($LASTEXITCODE -ne 0) {
      # Check for merge conflict (HTTP 422)
      if ($output -match "422|merge conflict") {
        throw "Cannot auto-resolve conflicts - consider closing PR (bot will recreate)"
      }
      throw "gh api failed: $output"
    }

    Write-Verbose "Updated PR #$Number branch"

  } catch {
    throw "Failed to update PR #${Number} branch: $_"
  }
}

function Close-PR {
  param(
    [Parameter(Mandatory)]
    [string]$Repo,

    [Parameter(Mandatory)]
    [int]$Number,

    [string]$Comment
  )

  Test-GitHubCLI

  try {
    if ($Comment) {
      $null = & gh pr comment $Number --repo $Repo --body $Comment 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to add comment to PR #${Number}"
      }
    }

    $null = & gh pr close $Number --repo $Repo --delete-branch 2>&1

    if ($LASTEXITCODE -ne 0) {
      throw "gh pr close failed (exit code: $LASTEXITCODE)"
    }

    Write-Verbose "Closed PR #$Number"

  } catch {
    throw "Failed to close PR #${Number}: $_"
  }
}

Export-ModuleMember -Function Test-GitHubCLI, Get-CurrentRepo, Get-BotPRs, Merge-PR, Update-PRBranch, Close-PR
