# Bot detection and information
# Cross-platform compatible

function Get-BotInfo {
    param(
        [Parameter(Mandatory)]
        [string]$Author
    )

    $config = Get-Config

    foreach ($botName in $config.bots.PSObject.Properties.Name) {
        $botConfig = $config.bots.$botName
        if ($botConfig.users -contains $Author) {
            return [PSCustomObject]@{
                name = $botName
                author = $Author
                enabled = $botConfig.enabled
            }
        }
    }

    # Unknown bot
    return [PSCustomObject]@{
        name = 'unknown'
        author = $Author
        enabled = $false
    }
}

function Test-IsBotAuthor {
    param(
        [Parameter(Mandatory)]
        [string]$Author,

        [string[]]$Bots
    )

    $config = Get-Config

    if (-not $Bots -or @($Bots).Count -eq 0) {
        # Check all enabled bots
        $Bots = $config.bots.PSObject.Properties.Name | Where-Object {
            $config.bots.$_.enabled
        }
    }

    foreach ($botName in $Bots) {
        $botConfig = $config.bots.$botName
        if ($botConfig -and $botConfig.users -contains $Author) {
            return $true
        }
    }

    return $false
}

function Get-EnabledBots {
    $config = Get-Config

    $enabled = @()
    foreach ($botName in $config.bots.PSObject.Properties.Name) {
        if ($config.bots.$botName.enabled) {
            $enabled += $botName
        }
    }

    return $enabled
}

function Add-BotUser {
    param(
        [Parameter(Mandatory)]
        [string]$BotName,

        [Parameter(Mandatory)]
        [string]$User
    )

    $config = Get-Config

    if (-not $config.bots.$BotName) {
        $config.bots | Add-Member -NotePropertyName $BotName -NotePropertyValue @{
            users = @($User)
            enabled = $true
        }
    } else {
        $users = [System.Collections.ArrayList]$config.bots.$BotName.users
        if ($users -notcontains $User) {
            $users.Add($User) | Out-Null
            $config.bots.$BotName.users = $users.ToArray()
        }
    }

    Save-Config -Config $config
    Write-Host "Added user '$User' to bot '$BotName'" -ForegroundColor Green
}

function Remove-BotUser {
    param(
        [Parameter(Mandatory)]
        [string]$BotName,

        [Parameter(Mandatory)]
        [string]$User
    )

    $config = Get-Config

    if (-not $config.bots.$BotName) {
        Write-Warning "Bot '$BotName' not found in configuration"
        return
    }

    $users = [System.Collections.ArrayList]$config.bots.$BotName.users
    if ($users -contains $User) {
        $users.Remove($User) | Out-Null
        $config.bots.$BotName.users = $users.ToArray()
        Save-Config -Config $config
        Write-Host "Removed user '$User' from bot '$BotName'" -ForegroundColor Green
    } else {
        Write-Warning "User '$User' not found in bot '$BotName'"
    }
}

function Enable-Bot {
    param(
        [Parameter(Mandatory)]
        [string]$BotName
    )

    $config = Get-Config

    if (-not $config.bots.$BotName) {
        Write-Warning "Bot '$BotName' not found in configuration"
        return
    }

    $config.bots.$BotName.enabled = $true
    Save-Config -Config $config
    Write-Host "Enabled bot '$BotName'" -ForegroundColor Green
}

function Disable-Bot {
    param(
        [Parameter(Mandatory)]
        [string]$BotName
    )

    $config = Get-Config

    if (-not $config.bots.$BotName) {
        Write-Warning "Bot '$BotName' not found in configuration"
        return
    }

    $config.bots.$BotName.enabled = $false
    Save-Config -Config $config
    Write-Host "Disabled bot '$BotName'" -ForegroundColor Yellow
}

Export-ModuleMember -Function Get-BotInfo, Test-IsBotAuthor, Get-EnabledBots, Add-BotUser, Remove-BotUser, Enable-Bot, Disable-Bot
