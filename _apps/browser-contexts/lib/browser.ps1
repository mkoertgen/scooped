# Browser detection and lock file management

# Browser path configurations: scoop path, standard paths, registry key
$script:BrowserPaths = @{
  chrome   = @{
    scoop    = $null
    paths    = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "${env:LocalAppData}\Google\Chrome\Application\chrome.exe")
    registry = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
  }
  edge     = @{
    scoop = $null
    paths = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe")
  }
  brave    = @{
    scoop = "scoop\apps\brave\current\brave.exe"
    paths = @("${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:LocalAppData}\BraveSoftware\Brave-Browser\Application\brave.exe")
  }
  chromium = @{
    scoop = "scoop\apps\ungoogled-chromium\current\chrome.exe"
    paths = @("${env:ProgramFiles}\Chromium\Application\chrome.exe", "${env:LocalAppData}\Chromium\Application\chrome.exe")
  }
  firefox  = @{
    scoop = "scoop\apps\firefox\current\firefox.exe"
    paths = @("${env:ProgramFiles}\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe")
  }
}

function Get-BrowserPath {
  param ([string]$Browser = "chrome")
  $cfg = $script:BrowserPaths[$Browser.ToLower()]
  if (-not $cfg) { return $null }
  # Check scoop installation first
  if ($cfg.scoop) {
    $scoopPath = Join-Path $env:USERPROFILE $cfg.scoop
    if (Test-Path $scoopPath) { return $scoopPath }
  }
  # Check standard paths
  foreach ($path in $cfg.paths) { if (Test-Path $path) { return $path } }
  # Check registry
  if ($cfg.registry) {
    $reg = Get-ItemProperty $cfg.registry -ErrorAction SilentlyContinue
    if ($reg) { return $reg.'(default)' }
  }
  return $null
}

function Test-ContextRunning {
  <#
  .SYNOPSIS
  Check if a browser context is already running.

  .DESCRIPTION
  Uses browser-specific lock file detection:
  - Chromium browsers: Fast lockfile check
  - Firefox: Lockfile + process verification (cleans stale locks)

  .PARAMETER Browser
  Browser type (chrome, edge, brave, firefox, etc.)

  .PARAMETER DataDir
  Path to the browser's user data directory
  #>
  param (
    [Parameter(Mandatory)][string]$Browser,
    [Parameter(Mandatory)][string]$DataDir
  )

  if ($Browser -eq "firefox") {
    # Firefox: Check lock file and verify process
    $lockFile = Join-Path $DataDir "parent.lock"
    if (Test-Path $lockFile) {
      # Verify Firefox process is actually running with this profile
      # Use WMI for PowerShell 5.1 compatibility (CommandLine property)
      $escapedPath = [regex]::Escape($DataDir)
      $process = Get-CimInstance Win32_Process -Filter "Name = 'firefox.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -match $escapedPath } |
      Select-Object -First 1

      if ($process) {
        return $true
      } else {
        # Stale lock file - Firefox crashed or was killed
        Write-Host "  Cleaning stale Firefox lock file" -ForegroundColor DarkGray
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        return $false
      }
    }
    return $false
  }

  # Chromium browsers (Chrome, Edge, Brave): Simple lockfile check
  $lockFiles = @("lockfile", "Singleton", "SingletonLock")
  $found = $lockFiles | ForEach-Object { Join-Path $DataDir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
  return [bool]$found
}

function Get-VSCodePath {
  # Prefer CLI wrapper (code.cmd) - properly detaches from console
  # The CLI wrapper handles the console detachment correctly on first launch
  $codeCli = Get-Command "code" -ErrorAction SilentlyContinue
  if ($codeCli) { return $codeCli.Source }

  # Fallback to Code.exe if CLI not in PATH
  $paths = @(
    "${env:LocalAppData}\Programs\Microsoft VS Code\bin\code.cmd",
    "${env:ProgramFiles}\Microsoft VS Code\bin\code.cmd",
    "${env:LocalAppData}\Programs\Microsoft VS Code\Code.exe",
    "${env:ProgramFiles}\Microsoft VS Code\Code.exe"
  )
  foreach ($path in $paths) {
    if (Test-Path $path) { return $path }
  }

  # Try VS Code Insiders
  $insiderPaths = @(
    "${env:LocalAppData}\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd",
    "${env:ProgramFiles}\Microsoft VS Code Insiders\bin\code-insiders.cmd",
    "${env:LocalAppData}\Programs\Microsoft VS Code Insiders\Code - Insiders.exe",
    "${env:ProgramFiles}\Microsoft VS Code Insiders\Code - Insiders.exe"
  )
  foreach ($path in $insiderPaths) {
    if (Test-Path $path) { return $path }
  }

  # Try scoop installations
  $scoopVSCode = Join-Path $env:USERPROFILE "scoop\apps\vscode\current\bin\code.cmd"
  if (Test-Path $scoopVSCode) { return $scoopVSCode }
  $scoopVSCodeExe = Join-Path $env:USERPROFILE "scoop\apps\vscode\current\Code.exe"
  if (Test-Path $scoopVSCodeExe) { return $scoopVSCodeExe }

  return $null
}

function Get-WorkspaceBasename {
  <#
  .SYNOPSIS
  Extract base filename from a workspace path (local or WSL).

  .DESCRIPTION
  Handles various workspace path formats:
  - Local paths: C:\path\to\workspace.code-workspace -> workspace
  - WSL paths: wsl://Ubuntu/path/to/workspace.code-workspace -> workspace
  - UNC WSL paths: \\wsl$\Ubuntu\path\to\workspace.code-workspace -> workspace
  #>
  param ([Parameter(Mandatory)][string]$WorkspacePath)

  # Remove .code-workspace extension if present
  $path = $WorkspacePath -replace '\.code-workspace$', ''

  # Extract the last segment (basename)
  if ($path -match '[/\\]([^/\\]+)$') {
    return $Matches[1]
  }
  return $path
}

function Close-VSCodeWindow {
  <#
  .SYNOPSIS
  Close a VS Code window by matching workspace name.

  .DESCRIPTION
  Uses Windows API to find and close a specific VS Code window by title.
  Matches pattern: "<workspace> (Workspace)" in window title.
  Works for both local and WSL workspaces.

  .PARAMETER WorkspaceBasename
  The workspace file basename (without .code-workspace extension).
  #>
  param ([Parameter(Mandatory)][string]$WorkspaceBasename)

  $windows = [WindowControl]::GetVSCodeWindows()

  foreach ($w in $windows) {
    # Pattern: "<optional-file> - <workspace> (Workspace) ..." or just "<workspace> (Workspace) ..."
    # Covers both local and WSL windows
    if ($w.Value -match "^(.+ - )?$([regex]::Escape($WorkspaceBasename)) \(Workspace\)") {
      [WindowControl]::SendMessage($w.Key, [WindowControl]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
      Write-Host "Closed VS Code window: $($w.Value)" -ForegroundColor Magenta
      return $true
    }
  }
  return $false
}
