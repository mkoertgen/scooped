# Open context and VS Code workspace

function Open-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [string[]]$ExtraUrls
  )

  $config = Get-Config

  # Check if context exists
  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found. Use 'list' to see available contexts or 'add' to create one."
    return
  }

  $ctx = $config.contexts.$ContextName
  $hasUrls = ($ctx.urls -and $ctx.urls.Count -gt 0) -or ($ExtraUrls -and $ExtraUrls.Count -gt 0)

  # Workspace-only context: has workspace but NO browser AND NO URLs
  if (-not $ctx.browser -and -not $hasUrls -and $ctx.workspace) {
    Write-Host "Opening workspace-only context: $ContextName" -ForegroundColor Green
    Open-VSCodeWorkspace -WorkspacePath $ctx.workspace
    return
  }

  # Browser context: Default to chrome if not specified (matches bc list behavior)
  $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }

  $browserPath = Get-BrowserPath $browser
  if (-not $browserPath) {
    Write-Error "Browser '$browser' not found."
    return
  }

  $dataDir = Get-ContextDataDir $ContextName

  # Ensure data directory exists for browser contexts
  if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "Created new context data directory: $dataDir" -ForegroundColor DarkGray
  }

  # Collect URLs
  $urls = @()
  if ($ctx.urls) { $urls += $ctx.urls }

  # Resolve ExtraUrls: could be bookmark names or actual URLs
  if ($ExtraUrls) {
    foreach ($item in $ExtraUrls) {
      # Check if it's a bookmark name
      if ($ctx.bookmarks -and ($ctx.bookmarks.PSObject.Properties.Name -contains $item)) {
        $urls += $ctx.bookmarks.$item
        Write-Host "  bookmark '$item': $($ctx.bookmarks.$item)" -ForegroundColor DarkGray
      } else {
        # Treat as URL
        $urls += $item
      }
    }
  }

  # Check if browser is already running
  $isRunning = Test-ContextRunning -Browser $browser -DataDir $dataDir

  if ($isRunning) {
    Write-Host "Context '$ContextName' is already running" -ForegroundColor Yellow
  } else {
    # Build arguments based on browser type
    if ($browser -eq "firefox") {
      # Firefox uses -profile
      $args = @("-profile", "`"$dataDir`"")
      if ($urls.Count -gt 0) {
        $args += $urls
      }
    } else {
      # Chromium-based browsers use --user-data-dir
      $args = @(
        "--user-data-dir=`"$dataDir`"",
        "--disable-session-crashed-bubble",  # Skip "Restore pages?" dialog
        "--hide-crash-restore-bubble"        # Hide crash restore bubble
      )
      if ($urls.Count -gt 0) {
        $args += $urls
      }
    }

    Write-Host "Opening $browser context: $ContextName" -ForegroundColor Green
    Start-Process $browserPath -ArgumentList $args
  }

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

  # Expand ~ and environment variables
  $expandedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspacePath)

  # Validate: must be a .code-workspace file
  if (-not ($expandedPath -match '\.code-workspace$')) {
    Write-Warning "Workspace must be a .code-workspace file: $expandedPath"
    Write-Warning "Use 'code --folder-uri' for folders, or create a workspace file."
    return
  }

  # Check for WSL remote format: wsl://<distro>/<path>
  if ($expandedPath -match '^wsl://([^/]+)(/.*)$') {
    $distro = $Matches[1]
    $wslPath = $Matches[2]
    Write-Host "Opening VS Code WSL workspace: $distro$wslPath" -ForegroundColor Magenta
    $fileUri = "vscode-remote://wsl+$distro$wslPath"
    Start-Process $vscodePath -ArgumentList "--file-uri", "`"$fileUri`"" -WindowStyle Hidden
    return
  }

  # Check for \\wsl$\ or \\wsl.localhost\ UNC paths
  if ($expandedPath -match '^\\\\wsl(\$|\.localhost)\\([^\\]+)\\(.*)$') {
    $distro = $Matches[2]
    $wslPath = "/" + ($Matches[3] -replace '\\', '/')
    Write-Host "Opening VS Code WSL workspace: $distro$wslPath" -ForegroundColor Magenta
    $fileUri = "vscode-remote://wsl+$distro$wslPath"
    Start-Process $vscodePath -ArgumentList "--file-uri", "`"$fileUri`"" -WindowStyle Hidden
    return
  }

  # Regular Windows path
  if (Test-Path $expandedPath) {
    Write-Host "Opening VS Code workspace: $expandedPath" -ForegroundColor Magenta
    Start-Process $vscodePath -ArgumentList "`"$expandedPath`"" -WindowStyle Hidden
  } else {
    Write-Warning "Workspace not found: $expandedPath"
  }
}
