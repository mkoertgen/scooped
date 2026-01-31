# browser-contexts

Isolated browser sessions with separate SSO/cookie/storage state. Each context gets its own `--user-data-dir`, providing complete isolation like Playwright browser contexts.

**Supports three context types:**

- **Browser + Workspace**: Full web dev (SSO isolation + code)
- **Browser only**: Web-only (testing, multi-tenant SSO)
- **Workspace only**: Backend/infra projects (no browser)

## Commands

| Command                                  | Description                                 |
| ---------------------------------------- | ------------------------------------------- |
| `list`                                   | Show all configured contexts                |
| `<context>`                              | Quick access - open a context               |
| `<context> <bookmark>`                   | Open context with specific bookmark(s)      |
| `show <context>`                         | Show details for a specific context         |
| `open <context> [urls...]`               | Open context with optional extra URLs       |
| `add <name> [-b browser] [-w workspace]` | Create a new context (browser or workspace) |
| `remove <name> [-DeleteData]`            | Remove a context                            |
| `urls <name> <url1> [url2...]`           | Set URLs for a context (replaces all)       |
| `add-url <name> <url>`                   | Add URL to a context (idempotent)           |
| `remove-url <name> <url>`                | Remove URL from a context                   |
| `bm <context>`                           | List bookmarks for a context                |
| `bm <context> add <name> <url>`          | Add a named bookmark                        |
| `bm <context> remove <name>`             | Remove a bookmark                           |
| `workspace <name> <path>`                | Set VS Code workspace (.code-workspace)     |
| `remove-workspace <name>`                | Remove workspace from a context             |
| `ps`                                     | Show running contexts with PID and uptime   |
| `close <context>`                        | Close browser and VS Code for context       |
| `export`                                 | Export config as JSON (for backup/dotfiles) |
| `import <file>`                          | Import config from JSON file                |
| `push <file>`                            | Export config + git-remotes (for sync)      |
| `pull <file> [--auto]`                   | Import config + restore git-remotes         |
| `config`                                 | Show configuration and available browsers   |

## Bookmarks

Named URLs for on-demand opening (vs `urls` which auto-open):

```powershell
bc bm secunet add azure https://portal.azure.com
bc bm secunet add s11-helpdesk https://helpdesk.syseleven.de
bc bm secunet                    # List all bookmarks
bc secunet azure                 # Open just the azure bookmark
bc secunet azure s11-helpdesk    # Open multiple bookmarks
```

## Workspace Support

Workspaces must be `.code-workspace` files (not folders):

```powershell
bc workspace acme "C:\work\acme\acme.code-workspace"
bc workspace contoso "wsl://Ubuntu/home/user/contoso.code-workspace"
```

WSL workspaces use the `wsl://Distro/path` shorthand and open with Remote - WSL.

## Use Cases

### Multi-tenant SSO Isolation

Work with multiple Azure tenants, AWS accounts, or any conflicting SSO sessions simultaneously:

```powershell
bc secunet      # Opens Chrome with secunet Azure tenant + workspace
bc barmenia     # Opens another Chrome with barmenia tenant
bc colenio      # Opens Chrome with colenio session
```

### Workspace-Only Projects

Backend, infrastructure, or documentation projects without browser needs:

```powershell
# Create workspace-only contexts
bc add api-service -w "C:\Projects\api-service.code-workspace"
bc add infra -w "C:\Projects\terraform.code-workspace"
bc add docs -w "wsl://Ubuntu/home/user/docs.code-workspace"

# Quick launch (just VS Code)
bc api-service
bc infra
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

## Sync Across Machines

Complete environment synchronization via git-based workflow.

### Setup (One Time)

```powershell
# Machine 1: Push to meta-repo (e.g., dotfiles)
bc push ~/dotfiles/.browser-contexts.json
cd ~/dotfiles
git add .browser-contexts.json *.code-workspace
git commit -m "Update browser-contexts"
git push
```

### Daily Workflow

```powershell
# Machine 2: Pull everything
git -C ~/dotfiles pull                          # Update meta-repo
bc pull ~/dotfiles/.browser-contexts.json --auto # Import + clone/pull repos

# Machine 1: Push changes
bc push ~/dotfiles/.browser-contexts.json
git -C ~/dotfiles add -A; git -C ~/dotfiles commit -m "Update"; git -C ~/dotfiles push
```

### What Gets Synced

**✓ Config**: All contexts (browsers, URLs, bookmarks, workspaces)
**✓ Workspace files**: `.code-workspace` files copied to meta-repo
**✓ Git remotes**: Repository URLs for auto-cloning
**✓ Auto-clone**: Missing repos cloned automatically with `--auto`
**✓ Auto-pull**: Existing repos updated via `git pull --ff-only`

### Commands

```powershell
bc push <file>              # Export config + workspace-files + git-remotes
bc pull <file>              # Interactive: Import config, prompt to clone repos
bc pull <file> --auto       # Automatic: Import + clone missing + pull all repos
```

### Example: New Machine Setup

```powershell
git clone git@github.com:user/dotfiles.git ~/dotfiles
bc pull ~/dotfiles/.browser-contexts.json --auto
# ✓ Contexts configured
# ✓ Workspace files copied
# ✓ All repos cloned and updated
# Ready to work!
```

**See [SYNC.md](SYNC.md) for detailed documentation.**

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
