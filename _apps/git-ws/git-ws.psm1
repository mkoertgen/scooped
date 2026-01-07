enum CommandType { help; pull; push; fetch; rebase; status; list }

function Find-WorkspaceFiles {
  param(
    [string]$Path = "."
  )
  Get-ChildItem -Path $Path -Filter "*.code-workspace" -ErrorAction SilentlyContinue
}

function Get-WorkspaceFolders {
  param(
    [Parameter(Mandatory)]
    [string]$WorkspaceFile
  )

  if (-not (Test-Path $WorkspaceFile)) {
    Write-Error "Workspace not found: $WorkspaceFile"
    return @()
  }

  $wsDir = Split-Path $WorkspaceFile -Parent
  $ws = Get-Content $WorkspaceFile | ConvertFrom-Json

  $folders = @()
  foreach ($folder in $ws.folders) {
    $repoPath = Join-Path $wsDir $folder.path | Resolve-Path -ErrorAction SilentlyContinue
    if ($repoPath -and (Test-Path "$repoPath\.git")) {
      $folders += $repoPath.Path
    }
  }
  return $folders
}

function Invoke-GitFetch {
  param(
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Push-Location $repo
    $remotes = git remote 2>$null
    if (-not $remotes) {
      Write-Host "[>] $name" -ForegroundColor DarkGray
      Write-Host "    No remote (local only)" -ForegroundColor DarkGray
      Pop-Location
      continue
    }
    Write-Host "[>] $name" -ForegroundColor Cyan
    git fetch --all --prune -q 2>&1 | Out-Null
    Write-Host "    Fetched" -ForegroundColor DarkGray
    Pop-Location
  }
  Write-Host "[OK] Done" -ForegroundColor Green
}

function Invoke-GitPull {
  param(
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Push-Location $repo
    $remotes = git remote 2>$null
    if (-not $remotes) {
      Write-Host "[>] $name" -ForegroundColor DarkGray
      Write-Host "    No remote (local only)" -ForegroundColor DarkGray
      Pop-Location
      continue
    }
    Write-Host "[>] $name" -ForegroundColor Cyan
    git fetch --all --prune -q 2>&1 | Out-Null
    $result = git pull --ff-only 2>&1
    if ($result -match "Already up to date") {
      Write-Host "    Up to date" -ForegroundColor DarkGray
    }
    elseif ($LASTEXITCODE -eq 0) {
      Write-Host "    Updated" -ForegroundColor Green
    }
    else {
      Write-Host "    $result" -ForegroundColor Yellow
    }
    Pop-Location
  }
  Write-Host "[OK] Done" -ForegroundColor Green
}

function Invoke-GitPush {
  param(
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Push-Location $repo
    $remotes = git remote 2>$null
    if (-not $remotes) {
      Write-Host "[>] $name" -ForegroundColor DarkGray
      Write-Host "    No remote (local only)" -ForegroundColor DarkGray
      Pop-Location
      continue
    }
    $ahead = git rev-list --count "@{u}..HEAD" 2>$null
    if ($ahead -eq 0) {
      Write-Host "[>] $name" -ForegroundColor DarkGray
      Write-Host "    Nothing to push" -ForegroundColor DarkGray
      Pop-Location
      continue
    }
    Write-Host "[>] $name" -ForegroundColor Cyan
    $result = git push 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Host "    Pushed $ahead commit(s)" -ForegroundColor Green
    }
    else {
      Write-Host "    $result" -ForegroundColor Yellow
    }
    Pop-Location
  }
  Write-Host "[OK] Done" -ForegroundColor Green
}

function Invoke-GitRebase {
  param(
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Push-Location $repo
    $remotes = git remote 2>$null
    if (-not $remotes) {
      Write-Host "[>] $name" -ForegroundColor DarkGray
      Write-Host "    No remote (local only)" -ForegroundColor DarkGray
      Pop-Location
      continue
    }
    Write-Host "[>] $name" -ForegroundColor Cyan
    git fetch --all --prune -q 2>&1 | Out-Null
    $result = git pull --rebase 2>&1
    if ($result -match "Already up to date") {
      Write-Host "    Up to date" -ForegroundColor DarkGray
    }
    elseif ($result -match "Current branch .* is up to date") {
      Write-Host "    Up to date" -ForegroundColor DarkGray
    }
    elseif ($LASTEXITCODE -eq 0) {
      Write-Host "    Rebased" -ForegroundColor Green
    }
    else {
      Write-Host "    $result" -ForegroundColor Yellow
    }
    Pop-Location
  }
  Write-Host "[OK] Done" -ForegroundColor Green
}

function Get-GitStatus {
  param(
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Push-Location $repo
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    $status = git status --porcelain 2>$null
    $ahead = git rev-list --count "@{u}..HEAD" 2>$null
    $behind = git rev-list --count "HEAD..@{u}" 2>$null

    $state = ""
    if ($status) { $state += " *" }
    if ($ahead -gt 0) { $state += " +$ahead" }
    if ($behind -gt 0) { $state += " -$behind" }

    if ($state) {
      Write-Host "[>] $name ($branch)$state" -ForegroundColor Yellow
    }
    else {
      Write-Host "[>] $name ($branch)" -ForegroundColor DarkGray
    }
    Pop-Location
  }
}

function Set-GitWorkspace {
<#
.SYNOPSIS
Git operations for VS Code workspace repositories.

.DESCRIPTION
Performs git operations (fetch, pull, status) on all repositories
defined in a VS Code .code-workspace file.

.PARAMETER Verb
The command to run: pull, fetch, status, list, help

.PARAMETER Workspace
Path to the .code-workspace file. Auto-detects if not specified.

.EXAMPLE
PS C:\> gws pull
Auto-detects workspace and pulls all repos.

.EXAMPLE
PS C:\> gws pull -Workspace .\my.code-workspace
Fetches and pulls all repos in the workspace.

.EXAMPLE
PS C:\> gws status
Shows git status for all repos.

.NOTES
Author: Marcel Koertgen
#>

  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [CommandType]$Verb,

    [Parameter()]
    [string]$Workspace
  )

  # Auto-detect workspace files if not specified
  if (-not $Workspace) {
    $wsFiles = Find-WorkspaceFiles
    if ($wsFiles.Count -eq 0) {
      Write-Error "No .code-workspace files found in current directory."
      return
    }
    elseif ($wsFiles.Count -eq 1) {
      $Workspace = $wsFiles[0].FullName
      Write-Host "Using: $($wsFiles[0].Name)" -ForegroundColor DarkGray
    }
    else {
      # Multiple workspaces: aggregate all
      Write-Host "Found $($wsFiles.Count) workspaces, aggregating..." -ForegroundColor DarkGray
      $allRepos = @()
      foreach ($wsFile in $wsFiles) {
        $allRepos += Get-WorkspaceFolders -WorkspaceFile $wsFile.FullName
      }
      $repos = $allRepos | Select-Object -Unique

      if ($repos.Count -eq 0 -and $Verb -ne [CommandType]::help) {
        Write-Error "No repos found in any workspace."
        return
      }

      switch ($Verb) {
        ([CommandType]::pull) { Invoke-GitPull -Repos $repos }
        ([CommandType]::push) { Invoke-GitPush -Repos $repos }
        ([CommandType]::fetch) { Invoke-GitFetch -Repos $repos }
        ([CommandType]::rebase) { Invoke-GitRebase -Repos $repos }
        ([CommandType]::status) { Get-GitStatus -Repos $repos }
        ([CommandType]::list) {
          foreach ($wsFile in $wsFiles) {
            Write-Host "Workspace: $($wsFile.Name)" -ForegroundColor Cyan
            $wsRepos = Get-WorkspaceFolders -WorkspaceFile $wsFile.FullName
            foreach ($repo in $wsRepos) {
              Write-Host "  $(Split-Path $repo -Leaf)" -ForegroundColor Gray
            }
          }
        }
        ([CommandType]::help) { Get-Help Set-GitWorkspace -Detailed }
      }
      return
    }
  }

  if (-not (Test-Path $Workspace)) {
    Write-Error "Workspace not found: $Workspace"
    return
  }

  $repos = Get-WorkspaceFolders -WorkspaceFile $Workspace

  if ($repos.Count -eq 0 -and $Verb -ne [CommandType]::help) {
    Write-Error "No repos found in workspace: $Workspace"
    return
  }

  switch ($Verb) {
    ([CommandType]::pull) {
      Invoke-GitPull -Repos $repos
    }
    ([CommandType]::push) {
      Invoke-GitPush -Repos $repos
    }
    ([CommandType]::fetch) {
      Invoke-GitFetch -Repos $repos
    }
    ([CommandType]::rebase) {
      Invoke-GitRebase -Repos $repos
    }
    ([CommandType]::status) {
      Get-GitStatus -Repos $repos
    }
    ([CommandType]::list) {
      Write-Host "Workspace: $Workspace" -ForegroundColor Cyan
      foreach ($repo in $repos) {
        Write-Host "  $(Split-Path $repo -Leaf)" -ForegroundColor Gray
      }
    }
    ([CommandType]::help) {
      Get-Help Set-GitWorkspace -Detailed
    }
    default {
      Write-Error "Unsupported command: $Verb"
    }
  }
}

New-Alias -Name gws -Value Set-GitWorkspace
Export-ModuleMember -Function Set-GitWorkspace -Alias gws
