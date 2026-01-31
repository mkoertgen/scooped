# Config management functions

function Load-Json {
  <#
  .SYNOPSIS
  Load JSON or JSONC (JSON with Comments) file.

  .DESCRIPTION
  Handles JSON with:
  - Comments (// single-line)
  - Trailing commas
  - UTF-8 encoding (with or without BOM)
  Common in VS Code workspace files and config files.

  Note: Comments are stripped - they won't be preserved on Save-Json.
  #>
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    throw "File not found: $Path"
  }

  $json = Get-Content $Path -Raw -Encoding UTF8
  # Strip single-line comments (// ...)
  $json = $json -replace '(?m)^\s*//.*$', ''
  $json = $json -replace '//[^"]*$', ''
  # Remove trailing commas before ] or }
  $json = $json -replace ',\s*([\]\}])', '$1'

  return $json | ConvertFrom-Json
}

function Save-Json {
  <#
  .SYNOPSIS
  Save object as JSON with UTF-8 encoding (no BOM) and proper formatting.

  .DESCRIPTION
  PowerShell's default JSON handling is problematic:
  - Set-Content -Encoding UTF8 adds BOM
  - ConvertTo-Json uses inconsistent indentation
  This helper provides consistent, portable JSON output.
  #>
  param(
    [Parameter(Mandatory)]
    [object]$Object,
    [Parameter(Mandatory)]
    [string]$Path,
    [int]$Depth = 10
  )

  $json = $Object | ConvertTo-Json -Depth $Depth
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
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

function Test-ContextExists {
  param ([object]$Config, [string]$Name)
  return $Config.contexts.PSObject.Properties.Name -contains $Name
}

function Save-Config {
  param ([Parameter(Mandatory)][object]$Config)
  Save-Json -Object $Config -Path $script:ConfigPath
  Write-Host "Config saved to $script:ConfigPath" -ForegroundColor DarkGray
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

function Show-ContextDetail {
  param (
    [Parameter(Mandatory)][string]$ContextName
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found. Use 'list' to see available contexts."
    return
  }

  $ctx = $config.contexts.$ContextName
  $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }
  $dataDir = Get-ContextDataDir $ContextName
  $exists = Test-Path $dataDir
  $status = if ($exists) { "initialized" } else { "new" }

  Write-Host "`nContext: $ContextName" -ForegroundColor Cyan
  Write-Host "  browser:   $browser"
  Write-Host "  status:    $status"
  Write-Host "  dataDir:   $dataDir"

  if ($ctx.workspace) {
    Write-Host "  workspace: $($ctx.workspace)" -ForegroundColor Magenta
  }

  if ($ctx.urls -and $ctx.urls.Count -gt 0) {
    Write-Host "  urls:"
    foreach ($url in $ctx.urls) {
      Write-Host "    - $url" -ForegroundColor DarkGray
    }
  }

  if ($ctx.bookmarks -and $ctx.bookmarks.PSObject.Properties.Count -gt 0) {
    Write-Host "  bookmarks:"
    foreach ($prop in $ctx.bookmarks.PSObject.Properties) {
      Write-Host "    $($prop.Name): " -NoNewline -ForegroundColor Yellow
      Write-Host $prop.Value -ForegroundColor DarkGray
    }
  }
  Write-Host ""
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
  Write-Host "`nVS Code:" -ForegroundColor Cyan
  $vscodePath = Get-VSCodePath
  if ($vscodePath) {
    Write-Host "  vscode" -ForegroundColor Green -NoNewline
    Write-Host " -> $vscodePath" -ForegroundColor DarkGray
  } else {
    Write-Host "  vscode" -ForegroundColor DarkGray -NoNewline
    Write-Host " (not found)" -ForegroundColor DarkGray
  }
  Write-Host ""
}
