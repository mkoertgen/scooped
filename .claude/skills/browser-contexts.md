# browser-contexts

Isolated browser sessions with separate SSO/cookie/storage state. Each context gets its own `--user-data-dir`, providing complete isolation like Playwright browser contexts.

## Commands

| Command                             | Description                                 |
| ----------------------------------- | ------------------------------------------- |
| `list`                              | Show all configured contexts                |
| `<context>`                         | Quick access - open a context               |
| `open <context> [urls...]`          | Open context with optional extra URLs       |
| `add <name> [-b browser] [-u urls]` | Create a new context                        |
| `remove <name> [-DeleteData]`       | Remove a context                            |
| `urls <name> <url1> [url2...]`      | Set URLs for a context (replaces all)       |
| `add-url <name> <url>`              | Add URL to a context (idempotent)           |
| `remove-url <name> <url>`           | Remove URL from a context                   |
| `ps`                                | Show running contexts with PID and uptime   |
| `kill <context>`                    | Stop a running context                      |
| `export`                            | Export config as JSON (for backup/dotfiles) |
| `import <file>`                     | Import config from JSON file                |
| `config`                            | Show configuration and available browsers   |

## Use Case

Multi-tenant SSO isolation - work with multiple Azure tenants, AWS accounts, or any conflicting SSO sessions simultaneously:

```powershell
bc secunet      # Opens Chrome with secunet Azure tenant
bc barmenia     # Opens another Chrome with barmenia tenant
bc colenio      # Opens Chrome with colenio session
```

## Configuration

- **Config file**: `~/.browser-contexts.json`
- **Data directory**: `~/.browser-contexts/<name>/`
- **Alias**: `bc` (via Scoop)

## Technical Details

- Chromium browsers: `--user-data-dir="path"`
- Firefox: `-profile "path"`
- Each context has its own cookies, localStorage, extensions, cached credentials
- Chrome's built-in "Restore pages" works per-context

## Backup

```powershell
bc export > ~/.dotfiles/.browser-contexts.json
bc import ~/.dotfiles/.browser-contexts.json
```
