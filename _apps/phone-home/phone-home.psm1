enum CommandType { help; status; startAll; stopAll; config; init; check }

function Stop-Services {
  param (
    [Parameter(Mandatory = $true)]
    [string[]]$Services
  )

  Write-Debug "Stopping services..."
  foreach ($name in $Services) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($service.Status -eq "Running") {
      Write-Debug "Stopping service '$($service.Name)'..."
      gsudo { Stop-Service -Name $args[0] } -args $service.Name
      Write-Host "Stopped service '$($service.Name)'."
    }
    if ($service.StartType -ne "Disabled") {
      Write-Debug "Disabling service '$($service.Name)'..." 
      gsudo { Set-Service -Name $args[0] -StartupType Disabled } -args $service.Name
      Write-Host "Disabled service '$($service.Name)'."
    }
  }
  Write-Host "Stopped services."
}

function Stop-Apps {
  param (
    [Parameter(Mandatory = $true)]
    [string[]]$Apps
  )

  Write-Debug "Stopping apps..."
  foreach ($name in $Apps) {
    $process = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($process) {
      Write-Debug "Stopping '$name'..."
      gsudo { Stop-Process -Name $args[0] -Force } -args $process.Name
      Write-Host "Stopped '$name'."
    }
  }
  Write-Host "Stopped apps."
}

function Find-App {
  param (
    [Parameter(Mandatory)]
    [string]$AppName
  )

  Write-Debug "Searching for app '$AppName'..."
  $app = Get-Command "$AppName.exe" -ErrorAction SilentlyContinue
  if ($app) {
    Write-Debug "Found '$AppName' at $($app.Source)"
    return $app.Source
  }

  Write-Debug "Searching for app '$AppName' in Start menu..."
  $app = Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu" -Recurse | Where-Object { $_.Name -like "*$AppName.lnk*" }
  if ($app) {
    Write-Debug "Found app '$AppName' in Start menu."
    return $app.FullName
  }

  $registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
  Write-Debug "Searching for app '$AppName' in Registry..."
  $app = Get-ChildItem $registryPaths | Get-ItemProperty | Where-Object { $_.DisplayName -like "* $AppName * " } | Select-Object -Property DisplayName, InstallLocation
  if ($app) {
    Write-Debug "Found app '$AppName' in Registry."
    return $app.InstallLocation
  }

  Write-Debug "Could not find app '$AppName'."
}

function Start-App {
  param (
    [Parameter(Mandatory)]
    [string]$AppName
  )

  Write-Debug "Starting app '$AppName'..."
  $command = Find-App -AppName $AppName
  if ($command) {
    Start-Process -FilePath $command
    Write-Host "Started app '$AppName'."
  }
  else {
    Write-Warning "Could not find app '$AppName'."
  }
}

function Start-Services {
  Write-Debug "Starting services..."
  foreach ($name in $services) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($service.StartType -ne "Manual") {
      Write-Debug "Enabling service '$($service.Name)'..."
      gsudo { Set-Service -Name $args[0] -StartupType Manual } -args $service.Name
      Write-Host "Enabled service '$($service.Name)'."
    }
    if ($service.Status -ne "Running") {
      Write-Debug "Starting service '$($service.Name)'..."
      gsudo { Start-Service -Name $args[0] } -args $service.Name
      Write-Host "Started service '$($service.Name)'."
    }
  }
  Write-Host "Started services."
}

function Check-Config {
  param (
    [Parameter(Mandatory)]
    [string[]]$Services,
    [Parameter(Mandatory)]
    [string[]]$Apps
  )
  foreach ($name in $Services) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($service) {
      Write-Host "Found service '$name'."
    }
    else {
      Write-Warning "Could not find service '$name'."
    }
  }

  foreach ($name in $Apps) {
    $command = Find-App -AppName $name
    if ($command) {
      Write-Host "Found app '$name' at '$command'."
    }
    else {
      Write-Warning "Could not find '$name'."
    }
  }
}

function Check-Status {
  param (
    [Parameter(Mandatory)]
    [string[]]$Services,
    [Parameter(Mandatory)]
    [string[]]$Apps
  )

  Write-Host "Services:"
  foreach ($name in $Services) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (!$service) {
      Write-Warning "  Could not find service '$name'."
      continue
    }
    Write-Host "  '$($service.Name)' is $($service.Status) and set to $($service.StartType)."
  }
  Write-Host "Apps:"
  foreach ($name in $Apps) {
    $process = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
      Write-Host "  '$($name)' is running."
    }
    else {
      Write-Host "  '$($name)' is not running."
    }
  }
}

$configFile = "$env:USERPROFILE\.phone-home.json"
$config = @{
  services = @(
    @{ name = "PanGPS" }
  )
  apps     = @(
    @{ name = "ms-teams" },
    @{ name = "OneDrive" },
    @{ name = "KeePassXC" },
    @{ name = "GoogleDriveFS"; link = "Google Drive" }
  )
}

if (Test-Path -Path $configFile) {
  Write-Debug "Found Config file at: $configFile"
  $config = Get-Content -Raw "$env:USERPROFILE\.phone-home.json" | ConvertFrom-Json
}

$services = $config.services | ForEach-Object { $_.name.Trim() }
$apps = $config.apps | Select-Object @{Name = 'Name'; Expression = { $_.'name' } }, @{Name = 'Link'; Expression = { If ($_.'link') { $_.'link' } Else { $_.'name' } } }
$appNames = $apps | ForEach-Object { $_.name.Trim() }
$appLinks = $apps | ForEach-Object { $_.link.Trim() }

function Set-PhoneHome {
  <#
.SYNOPSIS
This script manages your apps & services (starting, stopping, ...).

.LINK
This script uses [gsudo](https://github.com/gerardog/gsudo) to start/stop/find some apps & services.

.PARAMETER Command
The command to execute.

.EXAMPLE
PS C:\> .\phone-home.ps1 config
Config file: C:\Users\MKo\.phone-home.json
{"services":[{"name":"PanGPS"}],"apps":[{"name":"ms-teams"},{"name":"OneDrive"},{"name":"KeePassXC"},{"link":"Google Drive","name":"GoogleDriveFS"},{"name":"Docker Desktop"}]}

.EXAMPLE
PS C:\> .\phone-home.ps1 status
Config file: C:\Users\MKo\.phone-home.json
Services:
  PanGPS is Stopped and set to Disabled.
Apps:
  ms-teams is not running.
  OneDrive is not running.
  KeePassXC is not running.
  GoogleDriveFS is not running.
  Docker Desktop is not running.

.NOTES
Author: Marcel Körtgen <marcel.koertgen@gmail.com>
Date: 2023-10-08
#>

  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [CommandType]$Verb
  )

  switch ($Verb) {
    ([CommandType]::startAll) {
      Start-Services $services 
      Write-Debug "Starting apps..."
      foreach ($name in $appLinks) {
        Start-App -AppName $name
      }
      Write-Host "Started apps."
    }
    ([CommandType]::stopAll) {
      Stop-Services $services
      Stop-Apps $appNames
    }
    ([CommandType]::check) {
      Check-Config $services $appLinks
    }
    ([CommandType]::status) {
      Check-Status $services $appNames
    }
    ([CommandType]::config) {
      if (Test-Path -Path $configFile) {
        Write-Host "Config file: $configFile"
      }
      $config | ConvertTo-Json -Compress
    }
    ([CommandType]::init) {
      $config | ConvertTo-Json -Compress | Out-File -FilePath $configFile
      Write-Host "Created config file at: $configFile"
    }
    ([CommandType]::help) {
      Get-Help $MyInvocation.MyCommand.Name -Detailed
    }
    default {
      Write-Error "Unsupported command '$Verb'."
    }
  }
}

New-Alias -Name ph -Value Set-PhoneHome
Export-ModuleMember -Function Set-PhoneHome -Alias ph
