# phone-home

A PowerShell utility to manage apps and services that "phone home" - quickly start, stop, and control background processes.

## Location

- Source: `_apps/phone-home/`
- Entry: `phone-home.ps1` / `phone-home.cmd`
- Module: `phone-home.psm1`
- Config: `~/.phone-home.json`
- Scoop manifest: `bucket/phone-home.json`
- Alias: `ph`

## Commands

| Command     | Description                                 |
| ----------- | ------------------------------------------- |
| `ph status` | Show status of configured services and apps |
| `ph start`  | Start all configured services and apps      |
| `ph stop`   | Stop all configured services and apps       |
| `ph config` | Show current configuration                  |
| `ph init`   | Create default configuration file           |
| `ph check`  | Verify configured services/apps exist       |
| `ph help`   | Show help                                   |

## Use Case

Designed for consultants/developers switching between work contexts on the same workstation. Quickly disable/enable sets of applications and services when context-switching between clients or projects.

## Features

- Manages Windows services (start/stop, enable/disable)
- Manages applications (find and stop processes)
- Uses `gsudo` for transparent privilege escalation
- Configurable via JSON file
- Searches for apps in PATH, Start menu, and Registry

## Configuration

Config file `~/.phone-home.json`:

```json
{
  "services": ["ServiceName1", "ServiceName2"],
  "apps": ["AppName1", "AppName2"]
}
```

## Technical Details

- `Stop-Services` / `Start-Services` handle Windows services
- `Stop-Apps` terminates running processes
- `Find-App` searches multiple locations for executables
- Uses `gsudo` for admin operations without UAC prompts

## Development Notes

When modifying this tool:

- `CommandType` enum defines available commands
- Service operations use `Get-Service`, `Stop-Service`, `Set-Service`
- App operations use `Get-Process`, `Stop-Process`
- All admin commands wrapped in `gsudo { ... }`

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/phone-home
# Dependency for privilege escalation
scoop install gsudo
```
