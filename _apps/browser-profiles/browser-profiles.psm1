enum CommandType { help; list; open; config; add; remove }

$script:ConfigPath = Join-Path $env:USERPROFILE ".browser-profiles.json"

function Get-Config {
    if (Test-Path $script:ConfigPath) {
        return Get-Content $script:ConfigPath | ConvertFrom-Json
    }
    # Default config with empty aliases
    return [PSCustomObject]@{
        browser = "chrome"
        aliases = @{}
    }
}

function Get-Alias {
    param ([string]$Name)
    $config = Get-Config
    if ($config.aliases.PSObject.Properties.Name -contains $Name) {
        return $config.aliases.$Name
    }
    return $null
}

function Save-Config {
    param ([Parameter(Mandatory)][object]$Config)
    $Config | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath
    Write-Host "Config saved to $script:ConfigPath"
}

function Get-ChromePath {
    $paths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LocalAppData}\Google\Chrome\Application\chrome.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }
    # Try via registry
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
    if ($reg) { return $reg.'(default)' }
    return $null
}

function Get-ChromeProfiles {
    $userDataDir = Join-Path $env:LocalAppData "Google\Chrome\User Data"
    if (-not (Test-Path $userDataDir)) {
        Write-Warning "Chrome user data directory not found: $userDataDir"
        return @()
    }

    $profiles = @()
    $localState = Join-Path $userDataDir "Local State"
    if (Test-Path $localState) {
        $state = Get-Content $localState | ConvertFrom-Json
        $profileInfo = $state.profile.info_cache
        foreach ($prop in $profileInfo.PSObject.Properties) {
            $profiles += [PSCustomObject]@{
                Directory = $prop.Name
                Name      = $prop.Value.name
                Shortcut  = $prop.Value.shortcut_name
                Email     = $prop.Value.user_name
            }
        }
    }
    return $profiles
}

function Show-Profiles {
    $profiles = Get-ChromeProfiles
    $config = Get-Config

    if ($profiles.Count -eq 0) {
        Write-Host "No Chrome profiles found."
        return
    }

    Write-Host "`nChrome Profiles:" -ForegroundColor Cyan
    Write-Host "----------------"
    $profiles | ForEach-Object {
        $email = if ($_.Email) { " ($($_.Email))" } else { "" }
        # Find aliases for this profile
        $aliasNames = @()
        if ($config.aliases) {
            foreach ($prop in $config.aliases.PSObject.Properties) {
                if ($prop.Value -eq $_.Directory -or $prop.Value -eq $_.Name) {
                    $aliasNames += $prop.Name
                }
            }
        }
        $aliasText = if ($aliasNames.Count -gt 0) { " [" + ($aliasNames -join ", ") + "]" } else { "" }
        Write-Host "  $($_.Name)$email$aliasText" -ForegroundColor White
        Write-Host "    Directory: $($_.Directory)" -ForegroundColor DarkGray
    }

    Write-Host ""
}

function Open-Profile {
    param ([Parameter(Mandatory)][string]$ProfileName)

    $chromePath = Get-ChromePath
    if (-not $chromePath) {
        Write-Error "Chrome not found. Please install Chrome or specify the path."
        return
    }

    # First check aliases
    $aliasTarget = Get-Alias $ProfileName
    if ($aliasTarget) {
        Write-Host "Using alias '$ProfileName' -> '$aliasTarget'" -ForegroundColor DarkGray
        $ProfileName = $aliasTarget
    }

    $profiles = Get-ChromeProfiles
    $profile = $profiles | Where-Object {
        $_.Name -like "*$ProfileName*" -or $_.Directory -like "*$ProfileName*"
    } | Select-Object -First 1

    if (-not $profile) {
        Write-Error "Profile '$ProfileName' not found. Use 'list' to see available profiles."
        return
    }

    Write-Host "Opening Chrome with profile: $($profile.Name)" -ForegroundColor Green
    Start-Process $chromePath -ArgumentList "--profile-directory=`"$($profile.Directory)`""
}

function Add-Alias {
    param (
        [Parameter(Mandatory)][string]$AliasName,
        [Parameter(Mandatory)][string]$ProfileName
    )

    $profiles = Get-ChromeProfiles
    $profile = $profiles | Where-Object {
        $_.Name -like "*$ProfileName*" -or $_.Directory -like "*$ProfileName*"
    } | Select-Object -First 1

    if (-not $profile) {
        Write-Error "Profile '$ProfileName' not found. Use 'list' to see available profiles."
        return
    }

    $config = Get-Config
    if (-not $config.aliases) {
        $config | Add-Member -NotePropertyName "aliases" -NotePropertyValue @{} -Force
    }
    $config.aliases | Add-Member -NotePropertyName $AliasName -NotePropertyValue $profile.Directory -Force
    Save-Config $config
    Write-Host "Added alias '$AliasName' -> '$($profile.Name)' ($($profile.Directory))" -ForegroundColor Green
}

function Remove-Alias {
    param ([Parameter(Mandatory)][string]$AliasName)

    $config = Get-Config
    if ($config.aliases -and $config.aliases.PSObject.Properties.Name -contains $AliasName) {
        $config.aliases.PSObject.Properties.Remove($AliasName)
        Save-Config $config
        Write-Host "Removed alias '$AliasName'" -ForegroundColor Yellow
    } else {
        Write-Error "Alias '$AliasName' not found."
    }
}

function Show-Help {
    Write-Host @"

browser-profiles - Launch browser with specific profiles

Usage: browser-profiles <command> [options]

Commands:
  help                    Show this help message
  list                    List all available browser profiles
  open <name>             Open browser with the specified profile (partial match supported)
  alias <name> <profile>  Create an alias for a profile
  unalias <name>          Remove an alias
  config                  Show current configuration

Examples:
  browser-profiles list
  browser-profiles open Work
  browser-profiles alias private Marcel        # Create alias
  browser-profiles alias colenio "Profile 2"  # Create alias
  browser-profiles private                     # Quick access via alias
  browser-profiles unalias private             # Remove alias

Config: ~/.browser-profiles.json (not tracked in git)

"@ -ForegroundColor Cyan
}

function Show-Config {
    $config = Get-Config
    Write-Host "`nConfiguration:" -ForegroundColor Cyan
    Write-Host "  Config file: $script:ConfigPath"
    Write-Host "  Chrome path: $(Get-ChromePath)"

    if ($config.aliases -and $config.aliases.PSObject.Properties.Count -gt 0) {
        Write-Host "`nAliases:" -ForegroundColor Cyan
        foreach ($prop in $config.aliases.PSObject.Properties) {
            Write-Host "  $($prop.Name) -> $($prop.Value)" -ForegroundColor White
        }
    } else {
        Write-Host "`n  No aliases configured. Use 'alias <name> <profile>' to add one."
    }
    Write-Host ""
}

function Invoke-BrowserProfiles {
    param (
        [Parameter(Position = 0)][string]$Command = "help",
        [Parameter(Position = 1)][string[]]$Arguments
    )

    switch ($Command) {
        "help" { Show-Help }
        "list" { Show-Profiles }
        "open" {
            if ($Arguments.Count -eq 0) {
                Write-Error "Please specify a profile name. Use 'list' to see available profiles."
                return
            }
            Open-Profile $Arguments[0]
        }
        "alias" {
            if ($Arguments.Count -lt 2) {
                Write-Error "Usage: browser-profiles alias <alias-name> <profile-name>"
                return
            }
            Add-Alias $Arguments[0] ($Arguments[1..($Arguments.Count - 1)] -join " ")
        }
        "unalias" {
            if ($Arguments.Count -eq 0) {
                Write-Error "Usage: browser-profiles unalias <alias-name>"
                return
            }
            Remove-Alias $Arguments[0]
        }
        "config" { Show-Config }
        default {
            # Treat unknown command as profile name for quick access
            Open-Profile $Command
        }
    }
}

Export-ModuleMember -Function Invoke-BrowserProfiles
