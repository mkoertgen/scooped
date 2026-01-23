# Bookmark management functions

function Show-Bookmarks {
  param (
    [Parameter(Mandatory)][string]$ContextName
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName

  if (-not $ctx.bookmarks -or $ctx.bookmarks.PSObject.Properties.Count -eq 0) {
    Write-Host "No bookmarks for context '$ContextName'." -ForegroundColor DarkGray
    Write-Host "Add with: browser-contexts bm $ContextName add <name> <url>" -ForegroundColor DarkGray
    return
  }

  Write-Host "`nBookmarks for '$ContextName':" -ForegroundColor Cyan
  foreach ($prop in $ctx.bookmarks.PSObject.Properties) {
    Write-Host "  $($prop.Name): " -NoNewline -ForegroundColor Yellow
    Write-Host $prop.Value
  }
  Write-Host ""
}

function Add-Bookmark {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string]$BookmarkName,
    [Parameter(Mandatory)][string]$Url
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName

  if (-not $ctx.bookmarks) {
    $ctx | Add-Member -NotePropertyName "bookmarks" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }

  $ctx.bookmarks | Add-Member -NotePropertyName $BookmarkName -NotePropertyValue $Url -Force
  Save-Config $config

  Write-Host "Added bookmark '$BookmarkName' to '$ContextName':" -ForegroundColor Green
  Write-Host "  $Url"
}

function Remove-Bookmark {
  param (
    [Parameter(Mandatory)][string]$ContextName,
    [Parameter(Mandatory)][string]$BookmarkName
  )

  $config = Get-Config

  if (-not (Test-ContextExists $config $ContextName)) {
    Write-Error "Context '$ContextName' not found."
    return
  }

  $ctx = $config.contexts.$ContextName

  if (-not $ctx.bookmarks -or -not ($ctx.bookmarks.PSObject.Properties.Name -contains $BookmarkName)) {
    Write-Error "Bookmark '$BookmarkName' not found in context '$ContextName'."
    return
  }

  $ctx.bookmarks.PSObject.Properties.Remove($BookmarkName)
  Save-Config $config

  Write-Host "Removed bookmark '$BookmarkName' from '$ContextName'." -ForegroundColor Yellow
}
