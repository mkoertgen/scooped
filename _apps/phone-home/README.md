# phone-home

Quickly manage apps & services that are "phoning home" (start, stop, check status).

## The Problem

In consulting, you often switch between customer contexts on the same workstation. Each context may require different apps and services running:

- VPN clients (GlobalProtect, Cisco AnyConnect)
- Cloud sync (OneDrive, Google Drive, Dropbox)
- Chat apps (Teams, Slack)
- Password managers
- Docker, databases, etc.

Manually starting/stopping these for each context switch is tedious and easy to forget.

## The Solution

`phone-home` (alias: `ph`) acts as a power switch for a configurable set of workloads. One command to stop everything, one to start everything.

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/phone-home
```

Requires [gsudo](https://github.com/gerardog/gsudo) for privilege escalation (stopping services).

## Usage

```powershell
ph <command>
```

| Command    | Description                              |
| ---------- | ---------------------------------------- |
| `status`   | Show current state of apps and services  |
| `startAll` | Start all configured apps and services   |
| `stopAll`  | Stop all configured apps and services    |
| `config`   | Show current configuration               |
| `init`     | Create default config file               |
| `check`    | Verify all configured apps are findable  |
| `help`     | Show help                                |

## Configuration

Config file: `~/.phone-home.json`

```json
{
  "services": [
    { "name": "PanGPS" }
  ],
  "apps": [
    { "name": "ms-teams" },
    { "name": "OneDrive" },
    { "name": "KeePassXC" },
    { "name": "GoogleDriveFS", "link": "Google Drive" }
  ]
}
```

- **services**: Windows services (stopped and disabled when off)
- **apps**: Applications (killed when off, launched when on)
- **link**: Optional display name for Start Menu lookup

## Examples

```powershell
# Check what's currently running
$ ph status
Services:
  'PanGPS' is Stopped and set to Disabled.
Apps:
  'ms-teams' is not running.
  'OneDrive' is not running.

# Start everything for work
$ ph startAll
Started service 'PanGPS'.
Started app 'ms-teams'.
Started app 'OneDrive'.

# End of day - shut it all down
$ ph stopAll
Stopped service 'PanGPS'.
Disabled service 'PanGPS'.
Stopped 'ms-teams'.
Stopped 'OneDrive'.
```

## How It Works

1. **Services**: Uses `Stop-Service`/`Start-Service` and `Set-Service -StartupType` via gsudo
2. **Apps**: Uses `Stop-Process` to kill, searches PATH/Start Menu/Registry to launch
3. **Privilege escalation**: Handled transparently via [gsudo](https://github.com/gerardog/gsudo)

## Demo

[![asciicast](https://asciinema.org/a/612778.svg)](https://asciinema.org/a/612778)
