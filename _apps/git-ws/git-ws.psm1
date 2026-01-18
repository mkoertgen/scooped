# Known commands with special handling
$KnownCommands = @('help', 'pull', 'push', 'fetch', 'rebase', 'status', 'list')

# Windows API for getting foreground window title (VS Code workspace detection)
if (-not ([System.Management.Automation.PSTypeName]'ForegroundWindow').Type) {
  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class ForegroundWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int count);

    public static string GetTitle() {
        var sb = new StringBuilder(512);
        GetWindowText(GetForegroundWindow(), sb, 512);
        return sb.ToString();
    }
}
"@
}

function ConvertFrom-Jsonc {
  <#
  .SYNOPSIS
  Convert JSONC (JSON with Comments) to a PowerShell object.
  Handles trailing commas and // comments that VS Code workspace files may contain.
  #>
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string]$InputObject
  )
  # Remove single-line comments (// ...)
  $json = $InputObject -replace '(?m)^\s*//.*$', ''
  $json = $json -replace '//[^"]*$', ''
  # Remove trailing commas before ] or }
  $json = $json -replace ',\s*([\]\}])', '$1'
  return $json | ConvertFrom-Json
}

function Get-ActiveVSCodeWorkspaceName {
  <#
  .SYNOPSIS
  Get the workspace name from the active VS Code window title.
  #>
  $title = [ForegroundWindow]::GetTitle()
  # Pattern: "... - ws-colenio (Workspace) - Visual Studio Code"
  # Or: "... - ws-colenio (Workspace) [WSL: Ubuntu] - Visual Studio Code"
  if ($title -match '- (.+?) \(Workspace\).*Visual Studio Code') {
    return $Matches[1].Trim()
  }
  return $null
}

function Find-WorkspaceByName {
  <#
  .SYNOPSIS
  Find a workspace file by name, searching known workspace roots.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [string]$StartPath = (Get-Location).Path
  )

  $fileName = "$Name.code-workspace"

  # First: Search up the directory tree
  $dir = $StartPath
  while ($dir) {
    $wsFile = Get-ChildItem $dir -Filter $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wsFile) { return $wsFile.FullName }
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }
    $dir = $parent
  }

  # Second: Search known workspace roots (configurable via GIT_WORKSPACE_ROOT, default: ~/git)
  $gitRoot = if ($env:GIT_WORKSPACE_ROOT) { $env:GIT_WORKSPACE_ROOT } else { Join-Path $env:USERPROFILE "git" }
  if (Test-Path $gitRoot) {
    $wsFile = Get-ChildItem $gitRoot -Filter $fileName -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wsFile) { return $wsFile.FullName }
  }

  return $null
}

function Find-WorkspaceFiles {
  param(
    [string]$Path = "."
  )
  Get-ChildItem -Path $Path -Filter "*.code-workspace" -ErrorAction SilentlyContinue
}

function Find-WorkspaceForPath {
  <#
  .SYNOPSIS
  Find the workspace file that contains the given path.

  .DESCRIPTION
  Climbs up the directory tree looking for .code-workspace files,
  then checks which workspace actually contains the current path
  in its folders array.
  #>
  param(
    [string]$CurrentPath = (Get-Location).Path
  )

  $dir = $CurrentPath
  while ($dir) {
    $wsFiles = Get-ChildItem -Path $dir -Filter "*.code-workspace" -ErrorAction SilentlyContinue
    if ($wsFiles) {
      foreach ($wsFile in $wsFiles) {
        try {
          $ws = Get-Content $wsFile.FullName -Raw | ConvertFrom-Jsonc
          $wsDir = Split-Path $wsFile.FullName -Parent
          foreach ($folder in $ws.folders) {
            $folderPath = Join-Path $wsDir $folder.path | Resolve-Path -ErrorAction SilentlyContinue
            if ($folderPath -and $CurrentPath.ToLower().StartsWith($folderPath.Path.ToLower())) {
              return $wsFile.FullName
            }
          }
        } catch {
          # Skip malformed workspace files
          continue
        }
      }
    }
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }  # Root reached
    $dir = $parent
  }
  return $null
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
  $ws = Get-Content $WorkspaceFile -Raw | ConvertFrom-Jsonc

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
    } elseif ($LASTEXITCODE -eq 0) {
      Write-Host "    Updated" -ForegroundColor Green
    } else {
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
    } else {
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
    } elseif ($result -match "Current branch .* is up to date") {
      Write-Host "    Up to date" -ForegroundColor DarkGray
    } elseif ($LASTEXITCODE -eq 0) {
      Write-Host "    Rebased" -ForegroundColor Green
    } else {
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
    } else {
      Write-Host "[>] $name ($branch)" -ForegroundColor DarkGray
    }
    Pop-Location
  }
}

function Invoke-GitPassthrough {
  <#
  .SYNOPSIS
  Run arbitrary git command on all repos (passthrough for aliases).
  #>
  param(
    [Parameter(Mandatory)]
    [string]$Command,
    [Parameter(Mandatory)]
    [string[]]$Repos
  )

  foreach ($repo in $Repos) {
    $name = Split-Path $repo -Leaf
    Write-Host "[>] $name" -ForegroundColor Cyan
    Push-Location $repo
    git $Command 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Pop-Location
  }
  Write-Host "[OK] Done" -ForegroundColor Green
}

function Set-GitWorkspace {
  <#
.SYNOPSIS
Git operations for VS Code workspace repositories.

.DESCRIPTION
Performs git operations (fetch, pull, status) on all repositories
defined in a VS Code .code-workspace file.

.PARAMETER Verb
The command to run: pull, fetch, status, list, help, or any git command/alias (passthrough)

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
    [string]$Verb,

    [Parameter()]
    [string]$Workspace
  )

  # Auto-detect workspace files if not specified
  if (-not $Workspace) {
    # First: Try VS Code window title (works for folders outside climb path)
    $wsName = Get-ActiveVSCodeWorkspaceName
    if ($wsName) {
      $detected = Find-WorkspaceByName -Name $wsName
      if ($detected) {
        $Workspace = $detected
        Write-Host "Detected: $(Split-Path $Workspace -Leaf) (from VS Code)" -ForegroundColor DarkGray
      }
    }

    # Second: Try to find workspace that contains current directory (climb + parse)
    if (-not $Workspace) {
      $detected = Find-WorkspaceForPath
      if ($detected) {
        $Workspace = $detected
        Write-Host "Detected: $(Split-Path $Workspace -Leaf)" -ForegroundColor DarkGray
      }
    }

    # Fallback: Look for workspace files in current directory
    if (-not $Workspace) {
      $wsFiles = Find-WorkspaceFiles
      if ($wsFiles.Count -eq 0) {
        Write-Error "No workspace found. Use -Workspace to specify one."
        return
      } elseif ($wsFiles.Count -eq 1) {
        $Workspace = $wsFiles[0].FullName
        Write-Host "Using: $($wsFiles[0].Name)" -ForegroundColor DarkGray
      } else {
        # Multiple workspaces: aggregate all
        Write-Host "Found $($wsFiles.Count) workspaces, aggregating..." -ForegroundColor DarkGray
        $allRepos = @()
        foreach ($wsFile in $wsFiles) {
          $allRepos += Get-WorkspaceFolders -WorkspaceFile $wsFile.FullName
        }
        $repos = $allRepos | Select-Object -Unique

        if ($repos.Count -eq 0 -and $Verb -ne 'help') {
          Write-Error "No repos found in any workspace."
          return
        }

        switch ($Verb) {
          'pull' { Invoke-GitPull -Repos $repos }
          'push' { Invoke-GitPush -Repos $repos }
          'fetch' { Invoke-GitFetch -Repos $repos }
          'rebase' { Invoke-GitRebase -Repos $repos }
          'status' { Get-GitStatus -Repos $repos }
          'list' {
            foreach ($wsFile in $wsFiles) {
              Write-Host "Workspace: $($wsFile.Name)" -ForegroundColor Cyan
              $wsRepos = Get-WorkspaceFolders -WorkspaceFile $wsFile.FullName
              foreach ($repo in $wsRepos) {
                Write-Host "  $(Split-Path $repo -Leaf)" -ForegroundColor Gray
              }
            }
          }
          'help' { Get-Help Set-GitWorkspace -Detailed }
          default { Invoke-GitPassthrough -Command $Verb -Repos $repos }
        }
        return
      }
    }
  }

  if (-not (Test-Path $Workspace)) {
    Write-Error "Workspace not found: $Workspace"
    return
  }

  $repos = Get-WorkspaceFolders -WorkspaceFile $Workspace

  if ($repos.Count -eq 0 -and $Verb -ne 'help') {
    Write-Error "No repos found in workspace: $Workspace"
    return
  }

  switch ($Verb) {
    'pull' {
      Invoke-GitPull -Repos $repos
    }
    'push' {
      Invoke-GitPush -Repos $repos
    }
    'fetch' {
      Invoke-GitFetch -Repos $repos
    }
    'rebase' {
      Invoke-GitRebase -Repos $repos
    }
    'status' {
      Get-GitStatus -Repos $repos
    }
    'list' {
      Write-Host "Workspace: $Workspace" -ForegroundColor Cyan
      foreach ($repo in $repos) {
        Write-Host "  $(Split-Path $repo -Leaf)" -ForegroundColor Gray
      }
    }
    'help' {
      Get-Help Set-GitWorkspace -Detailed
    }
    default {
      Invoke-GitPassthrough -Command $Verb -Repos $repos
    }
  }
}

New-Alias -Name gws -Value Set-GitWorkspace
Export-ModuleMember -Function Set-GitWorkspace -Alias gws
