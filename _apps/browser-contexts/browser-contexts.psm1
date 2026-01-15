# Browser Contexts - Isolated browser sessions with separate SSO/cookie/storage state
# Uses --user-data-dir for complete isolation (like Playwright)

$script:ConfigPath = Join-Path $env:USERPROFILE ".browser-contexts.json"
$script:DefaultDataDir = Join-Path $env:USERPROFILE ".browser-contexts"

# Windows API for window enumeration and control (needed for WSL VS Code windows)
if (-not ([System.Management.Automation.PSTypeName]'WindowControl').Type) {
  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowControl {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public const uint WM_CLOSE = 0x0010;
    private static List<KeyValuePair<IntPtr, string>> windows = new List<KeyValuePair<IntPtr, string>>();

    private static bool EnumCallback(IntPtr hWnd, IntPtr lParam) {
        if (IsWindowVisible(hWnd)) {
            StringBuilder sb = new StringBuilder(512);
            GetWindowText(hWnd, sb, 512);
            string title = sb.ToString();
            if (!string.IsNullOrEmpty(title) && title.Contains("Visual Studio Code")) {
                windows.Add(new KeyValuePair<IntPtr, string>(hWnd, title));
            }
        }
        return true;
    }

    public static List<KeyValuePair<IntPtr, string>> GetVSCodeWindows() {
        windows.Clear();
        EnumWindows(EnumCallback, IntPtr.Zero);
        return new List<KeyValuePair<IntPtr, string>>(windows);
    }

    public static bool CloseWindowByTitlePattern(string pattern) {
        windows.Clear();
        EnumWindows(EnumCallback, IntPtr.Zero);
        foreach (var w in windows) {
            if (w.Value.Contains(pattern)) {
                SendMessage(w.Key, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                return true;
            }
        }
        return false;
    }
}
"@
}

function Get-Config {
  if (Test-Path $script:ConfigPath) {
    return Get-Content $script:ConfigPath | ConvertFrom-Json
  }
  # Default config
  return [PSCustomObject]@{
    dataDir  = $script:DefaultDataDir
    contexts = [PSCustomObject]@{}
  }
}

function Save-Config {
  param ([Parameter(Mandatory)][object]$Config)
  $Config | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath
  Write-Host "Config saved to $script:ConfigPath" -ForegroundColor DarkGray
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
  Close a VS Code window by matching its title pattern.

  .DESCRIPTION
  Uses Windows API to find and close a specific VS Code window.
  Useful for WSL workspaces where multiple windows share the same process.

  .PARAMETER TitlePattern
  A string pattern to match against the window title.
  #>
  param ([Parameter(Mandatory)][string]$TitlePattern)

  if ([WindowControl]::CloseWindowByTitlePattern($TitlePattern)) {
    Write-Host "Closed VS Code window matching: $TitlePattern" -ForegroundColor Magenta
    return $true
  }
  return $false
}

function Test-IsWslWorkspace {
  <#
  .SYNOPSIS
  Check if a workspace path is a WSL remote workspace.
  #>
  param ([Parameter(Mandatory)][string]$WorkspacePath)

  return ($WorkspacePath -match '^wsl://' -or
          $WorkspacePath -match '^\\\\wsl(\$|\.localhost)\\' -or
          $WorkspacePath -match '^vscode-remote://wsl\+')
}

function Get-VSCodePath {
  # Try VS Code
  $paths = @(
    "${env:LocalAppData}\Programs\Microsoft VS Code\Code.exe",
    "${env:ProgramFiles}\Microsoft VS Code\Code.exe"
  )
  foreach ($path in $paths) {
    if (Test-Path $path) { return $path }
  }

  # Try VS Code Insiders
  $insiderPaths = @(
    "${env:LocalAppData}\Programs\Microsoft VS Code Insiders\Code - Insiders.exe",
    "${env:ProgramFiles}\Microsoft VS Code Insiders\Code - Insiders.exe"
  )
  foreach ($path in $insiderPaths) {
    if (Test-Path $path) { return $path }
  }

  # Try scoop installations
  $scoopVSCode = Join-Path $env:USERPROFILE "scoop\apps\vscode\current\Code.exe"
  if (Test-Path $scoopVSCode) { return $scoopVSCode }

  return $null
}

function Get-BrowserPath {
  param ([string]$Browser = "chrome")

  switch ($Browser.ToLower()) {
    "chrome" {
      $paths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LocalAppData}\Google\Chrome\Application\chrome.exe"
      )
      foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
      }
      $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
      if ($reg) { return $reg.'(default)' }
    }
    "edge" {
      $paths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
      )
      foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
      }
    }
    "brave" {
      # Scoop installation
      $scoopPath = Join-Path $env:USERPROFILE "scoop\apps\brave\current\brave.exe"
      if (Test-Path $scoopPath) { return $scoopPath }
      # Standard installations
      $paths = @(
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:LocalAppData}\BraveSoftware\Brave-Browser\Application\brave.exe"
      )
      foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
      }
    }
    "chromium" {
      # Ungoogled Chromium via scoop
      $scoopPath = Join-Path $env:USERPROFILE "scoop\apps\ungoogled-chromium\current\chrome.exe"
      if (Test-Path $scoopPath) { return $scoopPath }
      # Portable/other installations
      $paths = @(
        "${env:ProgramFiles}\Chromium\Application\chrome.exe",
        "${env:LocalAppData}\Chromium\Application\chrome.exe"
      )
      foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
      }
    }
    "firefox" {
      # Scoop installation
      $scoopPath = Join-Path $env:USERPROFILE "scoop\apps\firefox\current\firefox.exe"
      if (Test-Path $scoopPath) { return $scoopPath }
      # Standard installations
      $paths = @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
      )
      foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
      }
    }
  }
  return $null
}

function Get-ContextDataDir {
  param ([string]$ContextName)
  $config = Get-Config
  $dataDir = if ($config.dataDir) { $config.dataDir } else { $script:DefaultDataDir }
  return Join-Path $dataDir $ContextName
}

function Show-Contexts {
  $config = Get-Config

  Write-Host "`nBrowser Contexts:" -ForegroundColor Cyan
  Write-Host "-----------------"

  $hasContexts = $false
  if ($config.contexts -and $config.contexts.PSObject.Properties.Count -gt 0) {
    foreach ($prop in $config.contexts.PSObject.Properties) {
      $hasContexts = $true
      $ctx = $prop.Value
      $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }
      $dataDir = Get-ContextDataDir $prop.Name
      $exists = Test-Path $dataDir
      $status = if ($exists) { "[initialized]" } else { "[new]" }

      Write-Host "  $($prop.Name)" -ForegroundColor White -NoNewline
      Write-Host " ($browser) $status" -ForegroundColor DarkGray

      if ($ctx.workspace) {
        Write-Host "    workspace: $($ctx.workspace)" -ForegroundColor Magenta
      }

      if ($ctx.urls) {
        foreach ($url in $ctx.urls) {
          Write-Host "    -> $url" -ForegroundColor DarkGray
        }
      }
    }
  }

  if (-not $hasContexts) {
    Write-Host "  No contexts configured yet." -ForegroundColor DarkGray
    Write-Host "  Use 'add <name>' to create one." -ForegroundColor DarkGray
  }
  Write-Host ""
}

function Open-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [string[]]$ExtraUrls
  )

  $config = Get-Config

  # Check if context exists
  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found. Use 'list' to see available contexts or 'add' to create one."
    return
  }

  $ctx = $config.contexts.$ContextName
  $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }
  $browserPath = Get-BrowserPath $browser

  if (-not $browserPath) {
    Write-Error "Browser '$browser' not found."
    return
  }

  $dataDir = Get-ContextDataDir $ContextName

  # Ensure data directory exists
  if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "Created new context data directory: $dataDir" -ForegroundColor DarkGray
  }

  # Collect URLs
  $urls = @()
  if ($ctx.urls) { $urls += $ctx.urls }
  if ($ExtraUrls) { $urls += $ExtraUrls }

  # Build arguments based on browser type
  if ($browser -eq "firefox") {
    # Firefox uses -profile
    $args = @("-profile", "`"$dataDir`"")
    if ($urls.Count -gt 0) {
      $args += $urls
    }
  } else {
    # Chromium-based browsers use --user-data-dir
    $args = @("--user-data-dir=`"$dataDir`"")
    if ($urls.Count -gt 0) {
      $args += $urls
    }
  }

  Write-Host "Opening $browser context: $ContextName" -ForegroundColor Green
  Start-Process $browserPath -ArgumentList $args

  # Open VS Code workspace if configured
  if ($ctx.workspace) {
    Open-VSCodeWorkspace -WorkspacePath $ctx.workspace
  }
}

function Open-VSCodeWorkspace {
  param (
    [Parameter(Mandatory)][string]$WorkspacePath
  )

  $vscodePath = Get-VSCodePath
  if (-not $vscodePath) {
    Write-Warning "VS Code not found. Install VS Code to use workspace feature."
    return
  }

  $expandedPath = [System.Environment]::ExpandEnvironmentVariables($WorkspacePath)

  # Check for WSL remote format: wsl://<distro>/<path> or wsl+<distro>://<path>
  if ($expandedPath -match '^wsl://([^/]+)(/.*)$') {
    $distro = $Matches[1]
    $wslPath = $Matches[2]
    Write-Host "Opening VS Code WSL workspace: $distro$wslPath" -ForegroundColor Magenta
    Start-Process $vscodePath -ArgumentList "--remote", "wsl+$distro", "`"$wslPath`""
    return
  }

  # Check for \\wsl$\ or \\wsl.localhost\ UNC paths
  if ($expandedPath -match '^\\\\wsl(\$|\.localhost)\\([^\\]+)\\(.*)$') {
    $distro = $Matches[2]
    $wslPath = "/" + ($Matches[3] -replace '\\', '/')
    Write-Host "Opening VS Code WSL workspace: $distro$wslPath" -ForegroundColor Magenta
    Start-Process $vscodePath -ArgumentList "--remote", "wsl+$distro", "`"$wslPath`""
    return
  }

  # Regular Windows path
  if (Test-Path $expandedPath) {
    Write-Host "Opening VS Code workspace: $expandedPath" -ForegroundColor Magenta
    Start-Process $vscodePath -ArgumentList "`"$expandedPath`""
  } else {
    Write-Warning "Workspace not found: $expandedPath"
  }
}

function Add-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [string]$Browser = "chrome",
    [string[]]$Urls,
    [string]$Workspace
  )

  $config = Get-Config

  # Ensure contexts exists
  if (-not $config.contexts) {
    $config | Add-Member -NotePropertyName "contexts" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }

  $contextObj = [PSCustomObject]@{
    browser = $Browser.ToLower()
  }

  if ($Urls -and $Urls.Count -gt 0) {
    $contextObj | Add-Member -NotePropertyName "urls" -NotePropertyValue $Urls
  }

  if ($Workspace) {
    $contextObj | Add-Member -NotePropertyName "workspace" -NotePropertyValue $Workspace
  }

  $config.contexts | Add-Member -NotePropertyName $ContextName -NotePropertyValue $contextObj -Force
  Save-Config $config

  Write-Host "Added context '$ContextName' (browser: $Browser)" -ForegroundColor Green
  if ($Urls) {
    Write-Host "  URLs: $($Urls -join ', ')" -ForegroundColor DarkGray
  }
  if ($Workspace) {
    Write-Host "  Workspace: $Workspace" -ForegroundColor Magenta
  }
}

function Remove-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [switch]$DeleteData
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $config.contexts.PSObject.Properties.Remove($ContextName)
  Save-Config $config
  Write-Host "Removed context '$ContextName'" -ForegroundColor Yellow

  if ($DeleteData) {
    $dataDir = Get-ContextDataDir $ContextName
    if (Test-Path $dataDir) {
      Remove-Item -Path $dataDir -Recurse -Force
      Write-Host "Deleted data directory: $dataDir" -ForegroundColor Yellow
    }
  } else {
    Write-Host "  Data directory preserved. Use -DeleteData to remove it." -ForegroundColor DarkGray
  }
}

function Set-ContextWorkspace {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string]$WorkspacePath
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $expandedPath = [System.Environment]::ExpandEnvironmentVariables($WorkspacePath)

  # Validate workspace path exists (skip validation for WSL URIs)
  $isWslUri = $expandedPath -match '^wsl://'
  $isWslUnc = $expandedPath -match '^\\\\wsl(\$|\.localhost)\\'

  if ($isWslUri) {
    # Validate WSL path by converting to UNC and checking
    if ($expandedPath -match '^wsl://([^/]+)(/.*)$') {
      $distro = $Matches[1]
      $wslPath = $Matches[2]
      $uncPath = "\\wsl.localhost\$distro" + ($wslPath -replace '/', '\')
      if (Test-Path $uncPath) {
        Write-Host "WSL path validated: $uncPath" -ForegroundColor DarkGray
      } else {
        Write-Warning "WSL path not found: $uncPath"
        $response = Read-Host "Add anyway? (y/N)"
        if ($response -ne "y") { return }
      }
    }
  } elseif ($isWslUnc) {
    if (-not (Test-Path $expandedPath)) {
      Write-Warning "WSL path not found: $expandedPath"
      $response = Read-Host "Add anyway? (y/N)"
      if ($response -ne "y") { return }
    }
  } elseif (-not (Test-Path $expandedPath)) {
    Write-Warning "Workspace not found: $expandedPath"
    $response = Read-Host "Add anyway? (y/N)"
    if ($response -ne "y") { return }
  }

  $config.contexts.$ContextName | Add-Member -NotePropertyName "workspace" -NotePropertyValue $WorkspacePath -Force
  Save-Config $config

  Write-Host "Updated workspace for '$ContextName':" -ForegroundColor Magenta
  Write-Host "  -> $WorkspacePath" -ForegroundColor DarkGray
}

function Remove-ContextWorkspace {
  param (
    [Parameter(Mandatory)][string]$ContextName
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName
  if (-not $ctx.workspace) {
    Write-Host "Context '$ContextName' has no workspace configured." -ForegroundColor Yellow
    return
  }

  $ctx.PSObject.Properties.Remove("workspace")
  Save-Config $config

  Write-Host "Removed workspace from '$ContextName'" -ForegroundColor Yellow
}

function Set-ContextUrls {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string[]]$Urls
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $config.contexts.$ContextName | Add-Member -NotePropertyName "urls" -NotePropertyValue $Urls -Force
  Save-Config $config

  Write-Host "Updated URLs for '$ContextName':" -ForegroundColor Green
  foreach ($url in $Urls) {
    Write-Host "  -> $url" -ForegroundColor DarkGray
  }
}

function Add-ContextUrl {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string[]]$Urls
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName
  $existingUrls = @()
  if ($ctx.urls) { $existingUrls = @($ctx.urls) }

  $added = @($Urls | Where-Object { $_ -notin $existingUrls })

  if ($added.Count -eq 0) {
    Write-Host "URLs already present in '$ContextName'." -ForegroundColor DarkGray
    return
  }

  $newUrls = $existingUrls + $added
  $config.contexts.$ContextName | Add-Member -NotePropertyName "urls" -NotePropertyValue $newUrls -Force
  Save-Config $config

  Write-Host "Added URL(s) to '$ContextName':" -ForegroundColor Green
  foreach ($url in $added) {
    Write-Host "  + $url" -ForegroundColor DarkGray
  }
}

function Remove-ContextUrl {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string]$Url
  )

  $config = Get-Config

  if (-not ($config.contexts.PSObject.Properties.Name -contains $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName
  if (-not $ctx.urls) {
    Write-Host "Context '$ContextName' has no URLs." -ForegroundColor Yellow
    return
  }

  $newUrls = @($ctx.urls) | Where-Object { $_ -ne $Url }
  $config.contexts.$ContextName | Add-Member -NotePropertyName "urls" -NotePropertyValue $newUrls -Force
  Save-Config $config

  Write-Host "Removed URL from '$ContextName':" -ForegroundColor Yellow
  Write-Host "  - $Url" -ForegroundColor DarkGray
}

function Get-RunningContexts {
  $config = Get-Config
  $dataDir = if ($config.dataDir) { $config.dataDir } else { $script:DefaultDataDir }

  $running = @()

  # Find all browser processes with our data dir
  $chromeProcs = Get-Process chrome, msedge, brave, firefox -ErrorAction SilentlyContinue
  foreach ($proc in $chromeProcs) {
    try {
      $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
      if ($cmdLine -and $cmdLine -like "*$dataDir*") {
        # Extract context name from path
        foreach ($ctxName in $config.contexts.PSObject.Properties.Name) {
          if ($cmdLine -like "*$dataDir\$ctxName*" -or $cmdLine -like "*$dataDir/$ctxName*") {
            # Only add main browser process (no --type=)
            if ($cmdLine -notlike "*--type=*") {
              $running += [PSCustomObject]@{
                Context   = $ctxName
                PID       = $proc.Id
                Browser   = $proc.ProcessName
                StartTime = $proc.StartTime
              }
            }
            break
          }
        }
      }
    } catch {}
  }
  return $running
}

function Show-RunningContexts {
  $running = Get-RunningContexts

  Write-Host "`nRunning Contexts:" -ForegroundColor Cyan
  Write-Host "-----------------"

  if ($running.Count -eq 0) {
    Write-Host "  No contexts currently running." -ForegroundColor DarkGray
  } else {
    foreach ($ctx in $running) {
      $uptime = (Get-Date) - $ctx.StartTime
      $uptimeStr = if ($uptime.TotalHours -ge 1) { "{0:N0}h {1:N0}m" -f $uptime.TotalHours, $uptime.Minutes } else { "{0:N0}m" -f $uptime.TotalMinutes }
      Write-Host "  $($ctx.Context)" -ForegroundColor Green -NoNewline
      Write-Host " ($($ctx.Browser), PID $($ctx.PID), up $uptimeStr)" -ForegroundColor DarkGray
    }
  }
  Write-Host ""
}

function Stop-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [switch]$Force
  )

  $config = Get-Config
  $ctx = $config.contexts.$ContextName
  $closed = $false

  # Close browser instances
  $running = Get-RunningContexts | Where-Object { $_.Context -eq $ContextName }
  foreach ($browser in $running) {
    try {
      Stop-Process -Id $browser.PID -Force:$Force
      Write-Host "Closed browser ($($browser.Browser), PID $($browser.PID))" -ForegroundColor Green
      $closed = $true
    } catch {
      Write-Error "Failed to close browser: $_"
    }
  }

  # Close VS Code instances for this workspace
  if ($ctx -and $ctx.workspace) {
    $workspacePath = $ctx.workspace
    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($workspacePath)

    if (Test-IsWslWorkspace $expandedPath) {
      # WSL workspace: close by window title (multiple windows share same process)
      # Window title format: "<basename> [WSL: <distro>] - Visual Studio Code"
      $basename = Get-WorkspaceBasename $expandedPath
      $titlePattern = "$basename [WSL: "

      if (Close-VSCodeWindow -TitlePattern $titlePattern) {
        $closed = $true
      } else {
        Write-Host "No VS Code WSL window found for: $basename" -ForegroundColor Yellow
      }
    } else {
      # Local workspace: close by process command line match
      $codeProcs = Get-Process Code, "Code - Insiders" -ErrorAction SilentlyContinue
      foreach ($proc in $codeProcs) {
        try {
          $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
          if ($cmdLine -and $cmdLine -like "*$expandedPath*") {
            Stop-Process -Id $proc.Id -Force:$Force
            Write-Host "Closed VS Code (PID $($proc.Id))" -ForegroundColor Magenta
            $closed = $true
          }
        } catch {}
      }
    }
  }

  if (-not $closed) {
    Write-Host "Context '$ContextName' is not running." -ForegroundColor Yellow
  }
}

function Export-ContextConfig {
  $config = Get-Config
  $config | ConvertTo-Json -Depth 10
}

function Import-ContextConfig {
  param ([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    return
  }

  $newConfig = Get-Content $Path | ConvertFrom-Json
  Save-Config $newConfig
  Write-Host "Imported config from: $Path" -ForegroundColor Green
}

function Show-Config {
  $config = Get-Config
  $dataDir = if ($config.dataDir) { $config.dataDir } else { $script:DefaultDataDir }

  Write-Host "`nConfiguration:" -ForegroundColor Cyan
  Write-Host "  Config file: $script:ConfigPath"
  Write-Host "  Data directory: $dataDir"

  Write-Host "`nAvailable browsers:" -ForegroundColor Cyan
  foreach ($browser in @("chrome", "edge", "brave", "firefox")) {
    $path = Get-BrowserPath $browser
    if ($path) {
      Write-Host "  $browser" -ForegroundColor Green -NoNewline
      Write-Host " -> $path" -ForegroundColor DarkGray
    } else {
      Write-Host "  $browser" -ForegroundColor DarkGray -NoNewline
      Write-Host " (not found)" -ForegroundColor DarkGray
    }
  }
  Write-Host "\nVS Code:" -ForegroundColor Cyan
  $vscodePath = Get-VSCodePath
  if ($vscodePath) {
    Write-Host "  vscode" -ForegroundColor Green -NoNewline
    Write-Host " -> $vscodePath" -ForegroundColor DarkGray
  } else {
    Write-Host "  vscode" -ForegroundColor DarkGray -NoNewline
    Write-Host " (not found)" -ForegroundColor DarkGray
  }  Write-Host ""
}

function Show-Help {
  Write-Host @"

browser-contexts - Isolated browser sessions with separate SSO/cookie/storage state

Usage: browser-contexts <command> [options]

Commands:
  list                         List all configured contexts
  <context>                    Open a context (quick access)
  open <context> [urls...]     Open context with optional extra URLs
  add <name> [-b browser] [-u urls] [-w workspace]  Add a new context
  remove <name> [-DeleteData]  Remove a context
  urls <name> <url1> [url2...] Set URLs for a context (replaces all)
  add-url <name> <url>         Add URL to a context
  remove-url <name> <url>      Remove URL from a context
  workspace <name> <path>      Set VS Code workspace for a context
  remove-workspace <name>      Remove workspace from a context
  ps                           Show running contexts
  close <context>              Close browser and VS Code for a context
  export                       Export config as JSON (pipe to file)
  import <file>                Import config from JSON file
  config                       Show configuration and available browsers
  help                         Show this help

Options for 'add':
  -b, -Browser    Browser to use: chrome, edge, brave, firefox (default: chrome)
  -u, -Urls       URLs to open automatically
  -w, -Workspace  Path to VS Code workspace (local or WSL remote)

Workspace formats:
  C:\path\to\project.code-workspace      Local Windows workspace file
  C:\path\to\folder                      Local folder
  wsl://Ubuntu/home/user/project         WSL remote folder (shorthand)
  \\wsl$\Ubuntu\home\user\project        WSL UNC path

Examples:
  browser-contexts add acme -b chrome
  browser-contexts add contoso -b chrome -u "https://portal.azure.com"
  browser-contexts add project -b chrome -w "C:\Projects\project.code-workspace"
  browser-contexts workspace acme "wsl://Ubuntu/home/user/acme"
  browser-contexts urls acme "https://dev.azure.com/acme" "https://teams.microsoft.com"
  browser-contexts acme                       # Quick access (opens browser + workspace)
  browser-contexts open acme https://...      # With extra URL
  browser-contexts remove old-context -DeleteData

How it works:
  Each context gets its own browser data directory (~/.browser-contexts/<name>/).
  This provides complete isolation: cookies, localStorage, SSO sessions, extensions.
  Like Playwright's browser contexts, but for manual browsing.

Config: ~/.browser-contexts.json

"@ -ForegroundColor Cyan
}

function Invoke-BrowserContexts {
  param (
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Arguments,
    [Alias("b")][string]$Browser = "chrome",
    [Alias("u")][string[]]$Urls,
    [Alias("w")][string]$Workspace,
    [switch]$DeleteData
  )

  switch ($Command.ToLower()) {
    "help" { Show-Help }
    "list" { Show-Contexts }
    "ps" { Show-RunningContexts }
    { $_ -in "close", "kill" } {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts close <context>"
        return
      }
      Stop-Context -ContextName $Arguments[0] -Force
    }
    "config" { Show-Config }
    "export" { Export-ContextConfig }
    "import" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts import <file.json>"
        return
      }
      Import-ContextConfig -Path $Arguments[0]
    }
    "add" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts add <name> [-b browser] [-u urls] [-w workspace]"
        return
      }
      $params = @{
        ContextName = $Arguments[0]
        Browser     = $Browser
      }
      if ($Urls) { $params.Urls = $Urls }
      if ($Workspace) { $params.Workspace = $Workspace }
      Add-Context @params
    }
    "remove" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts remove <name> [-DeleteData]"
        return
      }
      Remove-Context -ContextName $Arguments[0] -DeleteData:$DeleteData
    }
    "urls" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts urls <name> <url1> [url2...]"
        return
      }
      Set-ContextUrls -ContextName $Arguments[0] -Urls $Arguments[1..($Arguments.Count - 1)]
    }
    "add-url" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts add-url <name> <url>"
        return
      }
      Add-ContextUrl -ContextName $Arguments[0] -Urls $Arguments[1..($Arguments.Count - 1)]
    }
    "remove-url" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts remove-url <name> <url>"
        return
      }
      Remove-ContextUrl -ContextName $Arguments[0] -Url $Arguments[1]
    }
    "workspace" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts workspace <name> <workspace-path>"
        return
      }
      Set-ContextWorkspace -ContextName $Arguments[0] -WorkspacePath $Arguments[1]
    }
    "remove-workspace" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts remove-workspace <name>"
        return
      }
      Remove-ContextWorkspace -ContextName $Arguments[0]
    }
    "open" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts open <name> [urls...]"
        return
      }
      $extraUrls = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count - 1)] } else { @() }
      Open-Context -ContextName $Arguments[0] -ExtraUrls $extraUrls
    }
    default {
      # Treat unknown command as context name for quick access
      $config = Get-Config
      if ($config.contexts.PSObject.Properties.Name -contains $Command) {
        Open-Context -ContextName $Command -ExtraUrls $Arguments
      } else {
        Write-Error "Unknown command or context: '$Command'. Use 'help' for usage."
      }
    }
  }
}

Export-ModuleMember -Function Invoke-BrowserContexts
