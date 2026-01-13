# browser-profiles

A PowerShell utility to launch Chrome with specific user profiles.

## Location

- Source: `_apps/browser-profiles/`
- Entry: `browser-profiles.ps1` / `browser-profiles.cmd`
- Module: `browser-profiles.psm1`
- Config: `~/.browser-profiles.json`
- Scoop manifest: `bucket/browser-profiles.json`

## Commands

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `browser-profiles list`                  | List all Chrome profiles with emails and aliases  |
| `browser-profiles open <name>`           | Open Chrome with matching profile (partial match) |
| `browser-profiles <name>`                | Quick access - open profile directly              |
| `browser-profiles config`                | Show current configuration                        |
| `browser-profiles add <alias> <profile>` | Add alias for a profile                           |
| `browser-profiles remove <alias>`        | Remove an alias                                   |
| `browser-profiles help`                  | Show help                                         |

## Features

- Auto-discovers Chrome profiles from `Local State` JSON
- Partial name matching for profile selection
- Profile aliases stored in config file
- Shows profile email/account when available

## Technical Details

- Reads profiles from `%LOCALAPPDATA%\Google\Chrome\User Data\Local State`
- Launches Chrome with `--profile-directory` argument
- Config stored as JSON in user home directory

## Development Notes

When modifying this tool:

- `CommandType` enum defines available commands
- `Get-ChromeProfiles` reads Chrome's Local State
- `Open-Profile` handles alias resolution and partial matching
- Config uses `Get-Config` / `Save-Config` pattern

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/browser-profiles
```
