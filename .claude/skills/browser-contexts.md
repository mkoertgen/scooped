# browser-contexts

Isolated browser sessions with separate SSO/cookie/storage state. Each context gets its own `--user-data-dir`, providing complete isolation like Playwright browser contexts.

## Commands

| Command                             | Description                                 |
| ----------------------------------- | ------------------------------------------- |
| `list`                              | Show all configured contexts                |
| `<context>`                         | Quick access - open a context               |
| `show <context>`                    | Show details for a specific context         |
| `open <context> [urls...]`          | Open context with optional extra URLs       |
| `add <name> [-b browser] [-u urls]` | Create a new context                        |
| `remove <name> [-DeleteData]`       | Remove a context                            |
| `urls <name> <url1> [url2...]`      | Set URLs for a context (replaces all)       |
| `add-url <name> <url>`              | Add URL to a context (idempotent)           |
| `remove-url <name> <url>`           | Remove URL from a context                   |
| `workspace <name> <path>`           | Set VS Code workspace (.code-workspace)     |
| `remove-workspace <name>`           | Remove workspace from a context             |
| `ps`                                | Show running contexts with PID and uptime   |
| `close <context>`                   | Close browser and VS Code for context       |
| `export`                            | Export config as JSON (for backup/dotfiles) |
| `import <file>`                     | Import config from JSON file                |
| `config`                            | Show configuration and available browsers   |

## Workspace Support

Workspaces must be `.code-workspace` files (not folders):

```powershell
bc workspace acme "C:\work\acme\acme.code-workspace"
bc workspace contoso "wsl://Ubuntu/home/user/contoso.code-workspace"
```

WSL workspaces use the `wsl://Distro/path` shorthand and open with Remote - WSL.

## Use Case

Multi-tenant SSO isolation - work with multiple Azure tenants, AWS accounts, or any conflicting SSO sessions simultaneously:

```powershell
bc secunet      # Opens Chrome with secunet Azure tenant + workspace
bc barmenia     # Opens another Chrome with barmenia tenant
bc colenio      # Opens Chrome with colenio session
```

## Configuration

- **Config file**: `~/.browser-contexts.json`
- **Data directory**: `~/.browser-contexts/<name>/`
- **Alias**: `bc` (via Scoop)

## Development

For local development/testing, use `bcdev` function in `$PROFILE`:

```powershell
function bcdev {
  Import-Module "C:\path\to\browser-contexts.psm1" -Force
  Invoke-BrowserContexts @args
}
```

Test changes without reinstalling:

```powershell
bcdev list
bcdev show myctx
bcdev workspace myctx "C:\work\project.code-workspace"
```

## Technical Details

- Chromium browsers: `--user-data-dir="path"`
- Firefox: `-profile "path"`
- Each context has its own cookies, localStorage, extensions, cached credentials
- Chrome's built-in "Restore pages" works per-context
- WSL paths skip validation (distro may not be running)

## Backup

```powershell
bc export > ~/.dotfiles/.browser-contexts.json
bc import ~/.dotfiles/.browser-contexts.json
```

## Release Process

Releases are triggered by pushing a tag in format `<app>/<version>`:

```powershell
# 1. Commit changes
git add -A; git commit -m "feat(browser-contexts): add show command, workspace support"

# 2. Push commit
git push

# 3. Tag and push to trigger release workflow
git tag browser-contexts/0.5.0
git push --tags
```

The GitHub workflow automatically:

1. Downloads the tagged archive
2. Calculates SHA256 hash
3. Updates `bucket/browser-contexts.json` with version, hash, URL
4. Commits and pushes the manifest update
5. Creates a GitHub Release with auto-generated notes

Users get the update via `scoop update browser-contexts`.
