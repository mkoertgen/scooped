# Sync functions for workspace and git-remotes synchronization

function Get-WorkspaceFolders {
  <#
  .SYNOPSIS
  Parse workspace file and extract folder paths (as absolute paths).

  .DESCRIPTION
  Handles various workspace path formats:
  - Local paths: C:\path\to\workspace.code-workspace -> folders
  - WSL paths: wsl://Ubuntu/path/to/workspace.code-workspace (skipped)
  Returns absolute paths to git repository folders.
  #>
  param ([Parameter(Mandatory)][string]$WorkspacePath)

  # Expand ~ to $HOME
  $expandedPath = $WorkspacePath
  if ($expandedPath.StartsWith('~/') -or $expandedPath.StartsWith('~\')) {
    $expandedPath = Join-Path $env:USERPROFILE $expandedPath.Substring(2)
  } elseif ($expandedPath -eq '~') {
    $expandedPath = $env:USERPROFILE
  }

  $expandedPath = [System.Environment]::ExpandEnvironmentVariables($expandedPath)

  # Handle WSL paths - skip for now
  if ($expandedPath -match '^wsl://([^/]+)(/.*)$') {
    Write-Verbose "WSL workspace paths not supported for git-remote extraction: $expandedPath"
    return @()
  }

  if (-not (Test-Path $expandedPath)) {
    Write-Warning "Workspace file not found: $expandedPath"
    return @()
  }

  try {
    # Parse JSONC (VS Code workspace files support comments and trailing commas)
    $workspace = Load-Json -Path $expandedPath
    $baseDir = Split-Path $expandedPath -Parent

    $folders = @()
    foreach ($folder in $workspace.folders) {
      $folderPath = $folder.path
      # Resolve relative paths
      if (-not [System.IO.Path]::IsPathRooted($folderPath)) {
        $folderPath = Join-Path $baseDir $folderPath
      }
      $folders += [System.IO.Path]::GetFullPath($folderPath)
    }
    return $folders
  }
  catch {
    Write-Warning "Failed to parse workspace file: $_"
    return @()
  }
}

function Get-GitRemotes {
  <#
  .SYNOPSIS
  Collect git remotes for a specific context.

  .DESCRIPTION
  Returns a hashtable mapping repo name to primary remote URL.
  Format: @{ "repo-name" = "git@github.com:user/repo.git" }

  This is called per-context, so remotes are stored in context.gitRemotes
  instead of globally, solving the uniqueness problem.
  #>
  param ([Parameter(Mandatory)][PSCustomObject]$Context)

  $remotes = @{}

  if (-not $Context.workspace) {
    return $remotes
  }

  $folders = Get-WorkspaceFolders -WorkspacePath $Context.workspace

  foreach ($folderPath in $folders) {
    if (-not (Test-Path (Join-Path $folderPath ".git"))) {
      Write-Verbose "Not a git repo: $folderPath"
      continue
    }

    try {
      Push-Location $folderPath

      # Get primary remote (origin, or first available)
      $remoteList = @(git remote 2>$null)
      if ($remoteList.Count -gt 0) {
        $remoteName = $remoteList[0]
        $url = (git remote get-url $remoteName 2>$null)
        if ($url) {
          $repoName = Split-Path $folderPath -Leaf
          $remotes[$repoName] = $url.Trim()
        }
      }
    }
    catch {
      Write-Warning "Failed to get remotes for $folderPath : $_"
    }
    finally {
      Pop-Location
    }
  }

  return $remotes
}

function Export-ConfigWithRemotes {
  <#
  .SYNOPSIS
  Export config including git remotes per-context.

  .DESCRIPTION
  Collects git remotes for each context's workspace and stores them
  in context.gitRemotes instead of a global gitRemotes object.
  This solves the uniqueness problem with relative paths.

  Normalizes paths for portability:
  - Replaces $env:USERPROFILE with ~ for cross-machine compatibility
  #>

  $config = Get-Config
  Write-Host "`nCollecting git remotes per context..." -ForegroundColor Cyan

  $totalRepos = 0
  $exportContexts = @()
  $homePath = $env:USERPROFILE.TrimEnd('\')

  foreach ($contextName in $config.contexts.PSObject.Properties.Name) {
    $ctx = $config.contexts.$contextName

    $exportCtx = [PSCustomObject]@{
      profile = $ctx.profile
    }

    if ($ctx.workspace) {
      # Normalize workspace path for portability (~ and forward slashes)
      $workspacePath = $ctx.workspace
      if ($workspacePath.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) {
        $workspacePath = '~' + $workspacePath.Substring($homePath.Length)
      }
      $workspacePath = $workspacePath -replace '\\', '/'
      $exportCtx | Add-Member -NotePropertyName workspace -NotePropertyValue $workspacePath

      Write-Host "  Context: $contextName" -ForegroundColor DarkGray
      $remotes = Get-GitRemotes -Context $ctx

      if ($remotes.Count -gt 0) {
        $exportCtx | Add-Member -NotePropertyName gitRemotes -NotePropertyValue $remotes
        $totalRepos += $remotes.Count
        Write-Host "    Found: $($remotes.Count) repos" -ForegroundColor Green
      } else {
        Write-Host "    No git repos" -ForegroundColor DarkGray
      }
    }

    $exportContexts += @{ $contextName = $exportCtx }
  }

  # Rebuild contexts as hashtable
  $contextsHash = @{}
  foreach ($item in $exportContexts) {
    $contextsHash += $item
  }

  # Normalize dataDir path for portability (~ and forward slashes)
  $dataDir = $config.dataDir
  if ($dataDir.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) {
    $dataDir = '~' + $dataDir.Substring($homePath.Length)
  }
  $dataDir = $dataDir -replace '\\', '/'

  $exportData = [PSCustomObject]@{
    dataDir  = $dataDir
    contexts = [PSCustomObject]$contextsHash
  }

  Write-Host "Total: $totalRepos git repositories" -ForegroundColor Green
  return $exportData
}

function Restore-GitRemotes {
  <#
  .SYNOPSIS
  Restore git repositories from context.gitRemotes.

  .DESCRIPTION
  For each repository in context's gitRemotes:
  1. Find target directory from workspace folders
  2. Clone if missing (with AutoClone flag)
  3. Update remote if exists
  4. Optionally pull latest changes
  #>
  param (
    [Parameter(Mandatory)][PSCustomObject]$Context,
    [Parameter(Mandatory)][string]$ContextName,
    [switch]$AutoClone
  )

  if (-not $Context.gitRemotes) {
    Write-Verbose "No git remotes in context '$ContextName'"
    return
  }

  if ($Context.gitRemotes.PSObject.Properties.Count -eq 0) {
    Write-Verbose "Empty gitRemotes in context '$ContextName'"
    return
  }

  Write-Host "`n  Context: $ContextName" -ForegroundColor Cyan

  if (-not $Context.workspace) {
    Write-Warning "    No workspace configured, cannot restore"
    return
  }

  $folders = Get-WorkspaceFolders -WorkspacePath $Context.workspace
  $foldersByName = @{}
  foreach ($folder in $folders) {
    $repoName = Split-Path $folder -Leaf
    $foldersByName[$repoName] = $folder
  }

  foreach ($repoName in $Context.gitRemotes.PSObject.Properties.Name) {
    $remoteUrl = $Context.gitRemotes.$repoName
    $targetPath = $foldersByName[$repoName]

    if (-not $targetPath) {
      Write-Warning "    $repoName - Not in workspace, skipping"
      continue
    }

    # Check if folder exists
    if (-not (Test-Path $targetPath)) {
      Write-Host "    $repoName - Not found locally" -ForegroundColor Yellow

      if ($AutoClone) {
        $answer = "y"
      } else {
        $answer = Read-Host "      Clone from $remoteUrl ? (y/n)"
      }

      if ($answer -eq "y") {
        $parentDir = Split-Path $targetPath -Parent
        if (-not (Test-Path $parentDir)) {
          New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        Write-Host "      Cloning..." -ForegroundColor DarkGray
        $cloneOutput = git clone $remoteUrl $targetPath 2>&1

        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $targetPath ".git"))) {
          Write-Host "      Cloned successfully" -ForegroundColor Green
        } else {
          Write-Warning "      Clone failed: $cloneOutput"
        }
      }
      continue
    }

    # Check if it's a git repo
    if (-not (Test-Path (Join-Path $targetPath ".git"))) {
      Write-Warning "    $repoName - Exists but not a git repository"
      continue
    }

    # Update remote
    try {
      Push-Location $targetPath

      $currentRemote = git remote get-url origin 2>$null

      if ($currentRemote -ne $remoteUrl) {
        if ($currentRemote) {
          git remote set-url origin $remoteUrl 2>&1 | Out-Null
          Write-Host "    $repoName - Updated remote" -ForegroundColor Yellow
        } else {
          git remote add origin $remoteUrl 2>&1 | Out-Null
          Write-Host "    $repoName - Added remote" -ForegroundColor Green
        }
      } else {
        Write-Host "    $repoName - Remote OK" -ForegroundColor DarkGray
      }

      # Optionally pull
      if ($AutoClone) {
        git fetch --all --prune -q 2>&1 | Out-Null
        git pull --ff-only 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Write-Host "      Pulled latest changes" -ForegroundColor Green
        }
      }
    }
    finally {
      Pop-Location
    }
  }
}

function Push-ContextConfig {
  <#
  .SYNOPSIS
  Push config, git remotes, and workspace files to sync location.

  .DESCRIPTION
  Complete push workflow:
  1. Export config with git remotes (per-context)
  2. Copy workspace files to .browser-contexts subdirectory
  3. Optionally commit to meta-repo

  .EXAMPLE
  bc push ~/dotfiles/.browser-contexts.json

  .NOTES
  Recommended workflow:
  1. Run 'bc push ~/dotfiles/.browser-contexts.json'
  2. Commit and push the dotfiles repo
  3. On other machine: 'bc pull ~/dotfiles/.browser-contexts.json --auto'

  Workspace files are stored in ~/.dotfiles/.browser-contexts/ subdirectory
  to keep them organized and avoid cluttering the dotfiles root.
  #>
  param ([string]$Path)

  if (-not $Path) {
    Write-Error "Usage: browser-contexts push <file>"
    return
  }

  # Step 1: Export config with remotes (per-context)
  $exportData = Export-ConfigWithRemotes
  Save-Json -Object $exportData -Path $Path

  # Step 2: Copy workspace files to subdirectory
  Write-Host "`nCopying workspace files..." -ForegroundColor Cyan
  $config = Get-Config
  $configDir = Split-Path $Path -Parent
  $workspaceDir = Join-Path $configDir ".browser-contexts"

  if (-not (Test-Path $workspaceDir)) {
    New-Item -Path $workspaceDir -ItemType Directory -Force | Out-Null
  }

  $copiedCount = 0
  foreach ($contextName in $config.contexts.PSObject.Properties.Name) {
    $ctx = $config.contexts.$contextName

    if (-not $ctx.workspace) { continue }

    $localWorkspace = [System.Environment]::ExpandEnvironmentVariables($ctx.workspace)

    # Skip WSL workspaces
    if ($localWorkspace -match '^wsl://') {
      Write-Verbose "Skipping WSL workspace: $localWorkspace"
      continue
    }

    if (Test-Path $localWorkspace) {
      $workspaceName = Split-Path $localWorkspace -Leaf
      $targetPath = Join-Path $workspaceDir $workspaceName

      Copy-Item $localWorkspace $targetPath -Force
      Write-Host "  Copied: $workspaceName -> .browser-contexts/" -ForegroundColor Green
      $copiedCount++
    } else {
      Write-Warning "  Workspace not found: $($ctx.workspace)"
    }
  }

  Write-Host ""
  Write-Host "Push complete" -ForegroundColor Green
  Write-Host "  Config: $(Split-Path $Path -Leaf)" -ForegroundColor DarkGray
  if ($copiedCount -gt 0) {
    Write-Host "  Workspace files: $copiedCount in .browser-contexts/" -ForegroundColor DarkGray
  }

  # Count git repos
  try {
    $exportedConfig = Load-Json -Path $Path
    $repoCount = 0
    foreach ($contextName in $exportedConfig.contexts.PSObject.Properties.Name) {
      $ctx = $exportedConfig.contexts.$contextName
      if ($ctx.gitRemotes) {
        $repoCount += $ctx.gitRemotes.PSObject.Properties.Count
      }
    }
    Write-Host "  Git repos tracked: $repoCount" -ForegroundColor DarkGray
  } catch {
    Write-Verbose "Could not read repo count: $_"
  }

  # Hint about git commit
  if (Test-Path (Join-Path $configDir ".git")) {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  cd $configDir" -ForegroundColor DarkGray
    Write-Host "  git add .browser-contexts.json .browser-contexts/" -ForegroundColor DarkGray
    Write-Host "  git commit -m 'Update browser-contexts'" -ForegroundColor DarkGray
    Write-Host "  git push" -ForegroundColor DarkGray
  }
}

function Sync-WorkspaceFiles {
  <#
  .SYNOPSIS
  Copy workspace files from .browser-contexts subdirectory to local machine.

  .DESCRIPTION
  Looks for .code-workspace files in the .browser-contexts subdirectory
  and copies them to the local workspace locations if they don't exist.
  Use -Force to overwrite existing workspace files.
  #>
  param (
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][object]$Config,
    [switch]$Force
  )

  $configDir = Split-Path $ConfigPath -Parent
  $workspaceDir = Join-Path $configDir ".browser-contexts"

  if (-not (Test-Path $workspaceDir)) {
    Write-Host "No workspace files found in sync location" -ForegroundColor DarkGray
    return
  }

  Write-Host "`nSyncing workspace files..." -ForegroundColor Cyan

  $copiedCount = 0
  foreach ($contextName in $Config.contexts.PSObject.Properties.Name) {
    $ctx = $Config.contexts.$contextName

    if (-not $ctx.workspace) { continue }

    $localWorkspace = [System.Environment]::ExpandEnvironmentVariables($ctx.workspace)

    # Skip WSL workspaces
    if ($localWorkspace -match '^wsl://') {
      Write-Verbose "Skipping WSL workspace: $localWorkspace"
      continue
    }

    # Check if workspace file exists locally
    $workspaceName = Split-Path $localWorkspace -Leaf
    $sourceWorkspace = Join-Path $workspaceDir $workspaceName

    if (-not (Test-Path $sourceWorkspace)) {
      Write-Warning "  Workspace file not found in sync dir: $workspaceName"
      continue
    }

    if (-not (Test-Path $localWorkspace) -or $Force) {
      # Create parent directory if needed
      $parentDir = Split-Path $localWorkspace -Parent
      if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
      }

      # Copy workspace file
      Copy-Item $sourceWorkspace $localWorkspace -Force
      $action = if ((Test-Path $localWorkspace) -and $Force) { "Overwritten" } else { "Copied" }
      Write-Host "  ${action}: $workspaceName" -ForegroundColor Green
      $copiedCount++
    } else {
      Write-Host "  Exists: $workspaceName (use --force to overwrite)" -ForegroundColor DarkGray
    }
  }

  if ($copiedCount -gt 0) {
    $filesText = if ($copiedCount -eq 1) { "file" } else { "files" }
    Write-Host "Copied $copiedCount workspace $filesText" -ForegroundColor Green
  }
}

function Pull-ContextConfig {
  <#
  .SYNOPSIS
  Pull config from sync location and restore complete environment.

  .DESCRIPTION
  Complete pull workflow:
  1. Pull meta-repo (if in git repo) - gets latest config/workspace files
  2. Import config - load context definitions with per-context git remotes
  3. Sync workspace files - copy .code-workspace files from .browser-contexts/
  4. Restore git repos - clone missing repos, update remotes, pull changes

  .EXAMPLE
  # Interactive mode - prompts for each clone
  bc pull ~/dotfiles/.browser-contexts.json

  # Auto mode - clones and pulls everything automatically
  bc pull ~/dotfiles/.browser-contexts.json --auto

  # Force overwrite of existing workspace files
  bc pull ~/dotfiles/.browser-contexts.json --auto --force

  .NOTES
  Recommended setup:
  1. Store config in a git repo (e.g. dotfiles)
  2. Store .code-workspace files in .browser-contexts subdirectory
  3. Use 'bc push' to export from source machine
  4. Use 'bc pull --auto' on target machine to restore everything
  #>
  param (
    [Parameter(Mandatory)][string]$Path,
    [switch]$AutoClone,
    [switch]$Force
  )

  if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    return
  }

  $configDir = Split-Path $Path -Parent

  # Step 1: Pull meta-repo if in git
  if (Test-Path (Join-Path $configDir ".git")) {
    Write-Host "Pulling meta-repo updates..." -ForegroundColor Cyan
    try {
      Push-Location $configDir
      git pull --ff-only 2>$null
      if ($LASTEXITCODE -eq 0) {
        Write-Host "Meta-repo updated" -ForegroundColor Green
      } else {
        Write-Warning "Meta-repo pull failed - may have local changes"
      }
    }
    finally {
      Pop-Location
    }
  }

  # Step 2: Import config
  Write-Host "`nImporting config from: $Path" -ForegroundColor Cyan
  $importedConfig = Load-Json -Path $Path

  $mainConfig = [PSCustomObject]@{
    dataDir  = $importedConfig.dataDir
    contexts = $importedConfig.contexts
  }
  Save-Config $mainConfig
  Write-Host "Config imported" -ForegroundColor Green

  # Step 3: Sync workspace files from .browser-contexts subdirectory
  Sync-WorkspaceFiles -ConfigPath $Path -Config $importedConfig -Force:$Force

  # Step 4: Restore git remotes (per-context)
  Write-Host "`nRestoring git repositories..." -ForegroundColor Cyan
  foreach ($contextName in $importedConfig.contexts.PSObject.Properties.Name) {
    $ctx = $importedConfig.contexts.$contextName

    if ($ctx.gitRemotes) {
      Restore-GitRemotes -Context $ctx -ContextName $contextName -AutoClone:$AutoClone
    }
  }

  Write-Host ""
  Write-Host "Pull complete" -ForegroundColor Green
  Write-Host "  Run 'bc list' to see your contexts" -ForegroundColor DarkGray
}
