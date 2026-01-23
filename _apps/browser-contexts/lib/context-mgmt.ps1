# Context management (add, remove, rename, URLs, workspace)

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
