# Browser Contexts - Isolated browser sessions with separate SSO/cookie/storage state
# Uses --user-data-dir for complete isolation (like Playwright)

$script:ConfigPath = Join-Path $env:USERPROFILE ".browser-contexts.json"
$script:DefaultDataDir = Join-Path $env:USERPROFILE ".browser-contexts"

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
            $paths = @(
                "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
                "${env:LocalAppData}\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
            foreach ($path in $paths) {
                if (Test-Path $path) { return $path }
            }
        }
        "firefox" {
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
}

function Add-Context {
    param (
        [Parameter(Mandatory)][string]$ContextName,
        [string]$Browser = "chrome",
        [string[]]$Urls
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

    $config.contexts | Add-Member -NotePropertyName $ContextName -NotePropertyValue $contextObj -Force
    Save-Config $config

    Write-Host "Added context '$ContextName' (browser: $Browser)" -ForegroundColor Green
    if ($Urls) {
        Write-Host "  URLs: $($Urls -join ', ')" -ForegroundColor DarkGray
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
    Write-Host ""
}

function Show-Help {
    Write-Host @"

browser-contexts - Isolated browser sessions with separate SSO/cookie/storage state

Usage: browser-contexts <command> [options]

Commands:
  list                         List all configured contexts
  <context>                    Open a context (quick access)
  open <context> [urls...]     Open context with optional extra URLs
  add <name> [-b browser] [-u urls]  Add a new context
  remove <name> [-DeleteData]  Remove a context
  urls <name> <url1> [url2...] Set URLs for a context
  config                       Show configuration and available browsers
  help                         Show this help

Options for 'add':
  -b, -Browser   Browser to use: chrome, edge, brave, firefox (default: chrome)
  -u, -Urls      URLs to open automatically

Examples:
  browser-contexts add acme -b chrome
  browser-contexts add contoso -b chrome -u "https://portal.azure.com"
  browser-contexts urls acme "https://dev.azure.com/acme" "https://teams.microsoft.com"
  browser-contexts acme                       # Quick access
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
        [switch]$DeleteData
    )

    switch ($Command.ToLower()) {
        "help" { Show-Help }
        "list" { Show-Contexts }
        "config" { Show-Config }
        "add" {
            if (-not $Arguments -or $Arguments.Count -eq 0) {
                Write-Error "Usage: browser-contexts add <name> [-b browser] [-u urls]"
                return
            }
            Add-Context -ContextName $Arguments[0] -Browser $Browser -Urls $Urls
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
