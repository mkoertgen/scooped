# Context management (add, remove, rename, URLs, workspace)

function Add-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [string]$Browser,
    [string[]]$Urls,
    [string]$Workspace
  )

  $config = Get-Config

  # Ensure contexts exists
  if (-not $config.contexts) {
    $config | Add-Member -NotePropertyName "contexts" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }

  # Validate: must have either browser+urls OR workspace
  if (-not $Browser -and -not $Workspace) {
    Write-Error "Context must have at least a browser or a workspace. Use -b for browser or -w for workspace."
    return
  }

  $contextObj = [PSCustomObject]@{}

  if ($Browser) {
    $contextObj | Add-Member -NotePropertyName "browser" -NotePropertyValue $Browser.ToLower()
  }

  if ($Urls -and $Urls.Count -gt 0) {
    $contextObj | Add-Member -NotePropertyName "urls" -NotePropertyValue $Urls
  }

  if ($Workspace) {
    $contextObj | Add-Member -NotePropertyName "workspace" -NotePropertyValue $Workspace
  }

  $config.contexts | Add-Member -NotePropertyName $ContextName -NotePropertyValue $contextObj -Force
  Save-Config $config

  Write-Host "Added context '$ContextName'" -ForegroundColor Green
  if ($Browser) {
    Write-Host "  Browser: $Browser" -ForegroundColor DarkGray
  }
  if ($Urls) {
    Write-Host "  URLs: $($Urls -join ', ')" -ForegroundColor DarkGray
  }
  if ($Workspace) {
    Write-Host "  Workspace: $Workspace" -ForegroundColor Magenta
  }
  if (-not $Browser) {
    Write-Host "  (workspace-only, no browser)" -ForegroundColor DarkGray
  }
}

function Remove-Context {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [switch]$DeleteData
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
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

function Rename-Context {
  param (
    [Parameter(Mandatory)][string]$OldName,
    [Parameter(Mandatory)][string]$NewName,
    [switch]$Force
  )

  $config = Get-Config

  # Check if old context exists
  if (-not (Test-ContextExists $config $OldName)) {
    Write-Error "Context '$OldName' not found."
    return
  }

  # Check if new name already exists
  if (Test-ContextExists $config $NewName) {
    Write-Error "Context '$NewName' already exists."
    return
  }

  # Check if context is running
  $running = Get-RunningContexts | Where-Object { $_.Context -eq $OldName }
  if ($running) {
    if ($Force) {
      Write-Host "Closing running context '$OldName'..." -ForegroundColor Yellow
      Stop-Context -ContextName $OldName -Force
      Start-Sleep -Milliseconds 500
    } else {
      Write-Error "Context '$OldName' is running. Close it first or use -Force."
      return
    }
  }

  # Rename data directory
  $oldDataDir = Get-ContextDataDir $OldName
  $newDataDir = Get-ContextDataDir $NewName
  if (Test-Path $oldDataDir) {
    Move-Item -Path $oldDataDir -Destination $newDataDir -Force
    Write-Host "Renamed data directory: $OldName -> $NewName" -ForegroundColor DarkGray
  }

  # Rename config entry
  $ctxData = $config.contexts.$OldName
  $config.contexts.PSObject.Properties.Remove($OldName)
  $config.contexts | Add-Member -NotePropertyName $NewName -NotePropertyValue $ctxData -Force
  Save-Config $config

  Write-Host "Renamed context '$OldName' -> '$NewName'" -ForegroundColor Green
}

function Set-ContextWorkspace {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string]$WorkspacePath
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $expandedPath = [System.Environment]::ExpandEnvironmentVariables($WorkspacePath)

  # Skip validation for WSL URIs (distro might not be running)
  $isWslUri = $expandedPath -match '^wsl://'
  $isWslUnc = $expandedPath -match '^\\\\wsl(\$|\.localhost)\\'

  if (-not $isWslUri -and -not $isWslUnc) {
    # Only validate local Windows paths
    if (-not (Test-Path $expandedPath)) {
      Write-Warning "Workspace not found: $expandedPath"
      $response = Read-Host "Add anyway? (y/N)"
      if ($response -ne "y") { return }
    }
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

  if (-not (Test-ContextExists $config $ContextName)) {
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

  if (-not (Test-ContextExists $config $ContextName)) {
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

  if (-not (Test-ContextExists $config $ContextName)) {
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

  if (-not (Test-ContextExists $config $ContextName)) {
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

function New-WorkspaceFile {
  param (
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Folders,
    [string]$OutputPath,
    [switch]$CreateContext
  )

  # Resolve and validate folders
  $workspaceFolders = @()
  foreach ($folder in $Folders) {
    $resolvedPath = Resolve-Path $folder -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
      Write-Warning "Folder not found: $folder (skipping)"
      continue
    }

    $workspaceFolders += @{
      path = $resolvedPath.Path
    }
  }

  if ($workspaceFolders.Count -eq 0) {
    Write-Error "No valid folders found."
    return
  }

  # Create workspace JSON
  $workspace = @{
    folders = $workspaceFolders
    settings = @{}
  }

  # Determine output path
  if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) "$Name.code-workspace"
  }

  # Ensure .code-workspace extension
  if (-not $OutputPath.EndsWith('.code-workspace')) {
    $OutputPath += '.code-workspace'
  }

  # Write workspace file
  $workspace | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
  Write-Host "Created workspace file: $OutputPath" -ForegroundColor Green
  Write-Host "  Folders: $($workspaceFolders.Count)" -ForegroundColor DarkGray
  foreach ($f in $workspaceFolders) {
    Write-Host "    - $($f.path)" -ForegroundColor DarkGray
  }

  # Optionally create context
  if ($CreateContext) {
    $config = Get-Config
    if (Test-ContextExists $config $Name) {
      Write-Host "Context '$Name' already exists, updating workspace..." -ForegroundColor Yellow
      Set-ContextWorkspace -ContextName $Name -WorkspacePath $OutputPath
    } else {
      Write-Host "Creating workspace-only context '$Name'..." -ForegroundColor Cyan
      Add-Context -ContextName $Name -Workspace $OutputPath
    }
  }

  return $OutputPath
}
