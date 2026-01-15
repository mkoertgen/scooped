# browser-contexts

Isolated browser sessions with separate SSO/cookie/storage state. Perfect for multi-tenant environments where you need to be logged into multiple Azure tenants, AWS accounts, or any services that conflict with each other.

## The Problem

Working with multiple customers, each with their own:

- Azure Tenant / Entra ID
- Azure DevOps organization
- Microsoft 365 / Teams
- AWS Account
- GitHub organization

Switching between them is painful - SSO conflicts, cookie issues, having to log out and back in constantly.

## The Solution

Each "context" gets its own completely isolated browser data directory:

```
~/.browser-contexts/
  acme/        # Complete browser state for ACME Corp
  contoso/     # Complete browser state for Contoso Ltd
  personal/    # Your personal browsing
```

This is the same technique Playwright uses for browser isolation - each context has its own cookies, localStorage, session storage, extensions, and cached credentials.

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/browser-contexts
```

## Usage

```powershell
# Create contexts for your customers/environments
browser-contexts add acme -b chrome
browser-contexts add contoso -b chrome
browser-contexts add personal -b firefox

# Add default URLs (optional)
browser-contexts urls acme "https://portal.azure.com" "https://dev.azure.com/acme"
browser-contexts urls contoso "https://portal.azure.com" "https://dev.azure.com/contoso"

# Add VS Code workspace (optional) - opens alongside browser
browser-contexts workspace acme "C:\work\acme\acme.code-workspace"
browser-contexts workspace contoso "C:\work\contoso\project.code-workspace"

# Quick access - opens browser + workspace (if configured)
browser-contexts acme             # Opens isolated Chrome with acme session + VS Code
browser-contexts contoso          # Opens another isolated Chrome with contoso session + VS Code

# Open with additional URLs
browser-contexts open acme https://teams.microsoft.com

# List all contexts
browser-contexts list

# Remove a context (keeps data by default)
browser-contexts remove old-context
browser-contexts remove old-context -DeleteData  # Also deletes browser data
```

## How It Works

For Chromium-based browsers (Chrome, Edge, Brave):

```
chrome.exe --user-data-dir="~/.browser-contexts/acme"
```

For Firefox:

```
firefox.exe -profile "~/.browser-contexts/acme"
```

Each browser instance is completely independent - you can have multiple open simultaneously, each logged into different tenants.

## Configuration

Config file: `~/.browser-contexts.json`

```json
{
  "dataDir": "~/.browser-contexts",
  "contexts": {
    "acme": {
      "browser": "chrome",
      "urls": ["https://portal.azure.com", "https://dev.azure.com/acme"],
      "workspace": "C:\\work\\acme\\acme.code-workspace"
    },
    "contoso": {
      "browser": "chrome",
      "urls": ["https://portal.azure.com", "https://dev.azure.com/contoso"],
      "workspace": "wsl://Ubuntu/home/user/contoso.code-workspace"
    },
    "personal": {
      "browser": "firefox"
    }
  }
}
```

## Workspace Formats

The `workspace` field supports multiple formats:

| Format        | Example                                          | Description            |
| ------------- | ------------------------------------------------ | ---------------------- |
| Windows path  | `C:\work\project.code-workspace`                 | Local workspace file   |
| WSL shorthand | `wsl://Ubuntu/home/user/project.code-workspace`  | WSL remote workspace   |
| WSL UNC       | `\\wsl$\Ubuntu\home\user\project.code-workspace` | WSL UNC workspace path |

WSL workspaces open VS Code with the Remote - WSL extension.

## Supported Browsers

- **chrome** - Google Chrome
- **chromium** - Ungoogled Chromium (no Google sign-in prompts)
- **edge** - Microsoft Edge
- **brave** - Brave Browser
- **firefox** - Mozilla Firefox

Use `browser-contexts config` to see which browsers are detected on your system.

## Commands

| Command                                     | Description                            |
| ------------------------------------------- | -------------------------------------- |
| `list`                                      | Show all configured contexts           |
| `<context>`                                 | Quick access - open a context          |
| `open <context> [urls]`                     | Open context with optional extra URLs  |
| `add <name> [-b browser] [-u urls] [-w ws]` | Create a new context                   |
| `remove <name> [-DeleteData]`               | Remove a context                       |
| `urls <name> <url1> [url2...]`              | Set default URLs for a context         |
| `add-url <name> <url1> [url2...]`           | Add URL(s) to a context (idempotent)   |
| `remove-url <name> <url1> [url2...]`        | Remove URL(s) from a context           |
| `workspace <name> <path>`                   | Set VS Code workspace for a context    |
| `remove-workspace <name>`                   | Remove workspace from a context        |
| `ps`                                        | Show running browser contexts          |
| `close <context>`                           | Close browser and VS Code for context  |
| `export`                                    | Export config to stdout (pipe to file) |
| `import`                                    | Import config from stdin               |
| `config`                                    | Show config and available browsers     |
| `help`                                      | Show help                              |

## Tips

1. **First launch is slow** - Browser needs to initialize the new profile
2. **Extensions** - Install extensions separately in each context if needed
3. **Bookmarks** - Each context has its own bookmarks
4. **Sync** - You can sign into browser sync separately in each context
5. **Disk space** - Each context uses ~100-500MB depending on cache
6. **Camera/Microphone** - Permissions are per-context. Allow once per context via:
   - `chrome://settings/content/camera`
   - `chrome://settings/content/microphone`

## Alias

The `bc` command is installed automatically as a shim.

```powershell
# Use bc instead of browser-contexts
bc list
bc acme
bc add contoso chrome
```

## Development

For development and testing, add a wrapper function to your `$PROFILE`:

```powershell
function bcdev {
  Import-Module "C:\path\to\browser-contexts.psm1" -Force
  Invoke-BrowserContexts @args
}
```

This allows testing local changes without reinstalling the scoop package:

```powershell
# Test commands with local module
bcdev list
bcdev add test -b chrome
bcdev workspace myctx "C:\work\project.code-workspace"
bcdev show myctx
bcdev myctx
```

The `-Force` flag ensures the module is reloaded on each call, picking up any code changes immediately.
