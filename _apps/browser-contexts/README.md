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
scoop bucket add scooped https://github.com/mkoertgen/scooped
scoop install browser-contexts
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

# Quick access - just type the context name
browser-contexts acme             # Opens isolated Chrome with acme session
browser-contexts contoso          # Opens another isolated Chrome with contoso session

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
      "urls": ["https://portal.azure.com", "https://dev.azure.com/acme"]
    },
    "contoso": {
      "browser": "chrome",
      "urls": ["https://portal.azure.com", "https://dev.azure.com/contoso"]
    },
    "personal": {
      "browser": "firefox"
    }
  }
}
```

## Supported Browsers

- **chrome** - Google Chrome
- **edge** - Microsoft Edge
- **brave** - Brave Browser
- **firefox** - Mozilla Firefox

Use `browser-contexts config` to see which browsers are detected on your system.

## Commands

| Command                             | Description                           |
| ----------------------------------- | ------------------------------------- |
| `list`                              | Show all configured contexts          |
| `<context>`                         | Quick access - open a context         |
| `open <context> [urls]`             | Open context with optional extra URLs |
| `add <name> [-b browser] [-u urls]` | Create a new context                  |
| `remove <name> [-DeleteData]`       | Remove a context                      |
| `urls <name> <url1> [url2...]`      | Set default URLs for a context        |
| `config`                            | Show config and available browsers    |
| `help`                              | Show help                             |

## Tips

1. **First launch is slow** - Browser needs to initialize the new profile
2. **Extensions** - Install extensions separately in each context if needed
3. **Bookmarks** - Each context has its own bookmarks
4. **Sync** - You can sign into browser sync separately in each context
5. **Disk space** - Each context uses ~100-500MB depending on cache

## Alias (Optional)

Add to your PowerShell profile for shorter commands:

```powershell
Set-Alias bc browser-contexts
# or even shorter aliases for your most-used contexts:
function acme { browser-contexts acme @args }
function contoso { browser-contexts contoso @args }
```
