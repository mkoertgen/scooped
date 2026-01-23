# Configuration management for git-merge-bots
# Cross-platform compatible

function Get-ConfigPath {
    # Use platform-agnostic home directory
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        return Join-Path $env:USERPROFILE '.git-merge-bots.json'
    } else {
        return Join-Path $env:HOME '.git-merge-bots.json'
    }
}

function Get-DefaultConfig {
    return @{
        bots = @{
            dependabot = @{
                users = @('dependabot[bot]', 'dependabot-preview[bot]')
                enabled = $true
            }
            renovate = @{
                users = @('renovate[bot]', 'renovatebot')
                enabled = $true
            }
            snyk = @{
                users = @('snyk-bot')
                enabled = $true
            }
        }
        mergeStrategy = 'rebase'
        deleteBranch = $true
        skipCI = $false
        filters = @{
            excludeRepos = @()
            onlyPatch = $false
            requireCI = $true
        }
    }
}

function Get-Config {
    $configPath = Get-ConfigPath

    if (-not (Test-Path $configPath)) {
        Write-Verbose "Config file not found, creating default: $configPath"
        $config = Get-DefaultConfig
        Save-Config -Config $config
        return $config
    }

    try {
        $json = Get-Content $configPath -Raw -Encoding UTF8
        $config = $json | ConvertFrom-Json

        # Merge with defaults (in case new options were added)
        $defaultConfig = Get-DefaultConfig
        foreach ($key in $defaultConfig.Keys) {
            if (-not $config.PSObject.Properties.Name.Contains($key)) {
                $config | Add-Member -NotePropertyName $key -NotePropertyValue $defaultConfig[$key]
            }
        }

        return $config
    } catch {
        Write-Error "Failed to read config file: $_"
        return Get-DefaultConfig
    }
}

function Save-Config {
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $configPath = Get-ConfigPath

    try {
        $json = $Config | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $configPath -Encoding UTF8
        Write-Verbose "Config saved to $configPath"
    } catch {
        Write-Error "Failed to save config: $_"
    }
}

function Reset-Config {
    $config = Get-DefaultConfig
    Save-Config -Config $config
}

function Show-Config {
    $config = Get-Config
    $configPath = Get-ConfigPath

    Write-Host "Configuration ($configPath)" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Bots:" -ForegroundColor Yellow
    foreach ($bot in $config.bots.PSObject.Properties) {
        $enabled = if ($bot.Value.enabled) { '✓' } else { '✗' }
        Write-Host "  $enabled $($bot.Name)" -ForegroundColor White
        Write-Host "      Users: $($bot.Value.users -join ', ')" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Merge Settings:" -ForegroundColor Yellow
    Write-Host "  Strategy: $($config.mergeStrategy)" -ForegroundColor White
    Write-Host "  Delete branch: $($config.deleteBranch)" -ForegroundColor White
    Write-Host "  Skip CI: $($config.skipCI)" -ForegroundColor White

    Write-Host ""
    Write-Host "Filters:" -ForegroundColor Yellow
    Write-Host "  Require CI: $($config.filters.requireCI)" -ForegroundColor White
    Write-Host "  Only patch updates: $($config.filters.onlyPatch)" -ForegroundColor White
    if ($config.filters.excludeRepos.Count -gt 0) {
        Write-Host "  Excluded repos: $($config.filters.excludeRepos -join ', ')" -ForegroundColor White
    } else {
        Write-Host "  Excluded repos: (none)" -ForegroundColor Gray
    }
}

Export-ModuleMember -Function Get-ConfigPath, Get-Config, Save-Config, Reset-Config, Show-Config
