# git-merge-bots

Automatically merge bot PRs (Dependabot, Renovate, Snyk, etc.) across your repositories.

## Features

- ✅ **Multi-Bot Support**: Dependabot, Renovate, Snyk (extensible)
- ✅ **Cross-Platform**: Windows PowerShell 5.1+ and pwsh (Linux/macOS)
- ✅ **Safety First**: CI checks, conflict detection, dry-run mode
- ✅ **Flexible**: Per-repo config, multiple merge strategies
- ✅ **Workspace Integration**: Works with `git-ws` for multi-repo projects

## Installation

### Via Scoop (Windows)

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/git-merge-bots
```

### Manual Installation

```bash
# Clone or download
git clone https://github.com/mkoertgen/scooped.git
cd scooped/_apps/git-merge-bots

# Make executable (Linux/macOS)
chmod +x git-merge-bots.ps1

# Add to PATH or create alias
alias git-merge-bots='pwsh /path/to/git-merge-bots.ps1'
```

## Prerequisites

- **GitHub CLI** (`gh`): https://cli.github.com/
- **Git**: https://git-scm.com/
- **PowerShell**: Windows (built-in) or [PowerShell Core](https://github.com/PowerShell/PowerShell)

Authenticate with GitHub:

```bash
gh auth login
```

## Quick Start

```powershell
# List bot PRs in current repository
git-merge-bots list

# Dry-run: Show what would be merged
git-merge-bots merge --dry-run

# Merge all bot PRs (with safety checks)
git-merge-bots merge

# Merge only Dependabot PRs
git-merge-bots merge -Bots dependabot

# Merge in specific repository
git-merge-bots merge -Repo owner/repo
```

## Commands

### `list` - List bot PRs

```powershell
git-merge-bots list [options]

Options:
  -Repo <owner/repo>    Specific repository (default: current dir)
  -Bots <bot1,bot2>     Filter by bot names (default: all)
  -Status <status>      Filter by status: open, closed, all (default: open)
```

**Examples:**

```powershell
# List all bot PRs
git-merge-bots list

# List only Dependabot PRs
git-merge-bots list -Bots dependabot

# List in specific repo
git-merge-bots list -Repo mkoertgen/scooped
```

### `merge` - Merge bot PRs

```powershell
git-merge-bots merge [options]

Options:
  -Repo <owner/repo>    Specific repository (default: current dir)
  -Bots <bot1,bot2>     Filter by bot names (default: all)
  -Strategy <strategy>  Merge strategy: rebase, squash, merge (default: rebase)
  -DryRun               Show what would be merged without doing it
  -Force                Skip safety checks (conflicts, CI status)
```

**Examples:**

```powershell
# Dry-run to preview
git-merge-bots merge --dry-run

# Merge all bot PRs with rebase strategy
git-merge-bots merge

# Merge only Renovate PRs with squash
git-merge-bots merge -Bots renovate -Strategy squash

# Force merge (skip CI checks)
git-merge-bots merge --force
```

### `config` - Configuration management

```powershell
git-merge-bots config [options]

Options:
  -Show     Show current configuration
  -Edit     Open config file in editor
  -Reset    Reset to default configuration
```

## Configuration

Config file: `~/.git-merge-bots.json`

Default configuration:

```json
{
  "bots": {
    "dependabot": {
      "users": ["dependabot[bot]", "dependabot-preview[bot]"],
      "enabled": true
    },
    "renovate": {
      "users": ["renovate[bot]", "renovatebot"],
      "enabled": true
    },
    "snyk": {
      "users": ["snyk-bot"],
      "enabled": true
    }
  },
  "mergeStrategy": "rebase",
  "deleteBranch": true,
  "skipCI": false,
  "filters": {
    "excludeRepos": [],
    "onlyPatch": false,
    "requireCI": true
  }
}
```

### Customization

**Add custom bot:**

```json
{
  "bots": {
    "mybot": {
      "users": ["mybot[bot]"],
      "enabled": true
    }
  }
}
```

**Exclude specific repositories:**

```json
{
  "filters": {
    "excludeRepos": ["owner/critical-repo"]
  }
}
```

**Change default merge strategy:**

```json
{
  "mergeStrategy": "squash"
}
```

## Integration with git-ws

Use with [git-ws](https://github.com/mkoertgen/scooped/tree/main/_apps/git-ws) to merge bot PRs across all repositories in a VS Code workspace:

```powershell
# In directory with .code-workspace file
git ws merge-bots
git ws merge-bots --dry-run
```

git-ws will automatically call `git-merge-bots` for each repository in the workspace.

## Safety Features

**Automatic checks (skip with `--force`):**

- ✅ PR is mergeable (no conflicts)
- ✅ CI checks have passed
- ✅ PR is from configured bot user

**Best practices:**

- Always run `--dry-run` first
- Review PR changes before merging
- Use on non-critical repositories
- Keep CI checks enabled

## Use Cases

### 1. Reduce Notification Fatigue

Automatically merge dependency updates from bots on non-critical repositories:

```powershell
git-merge-bots merge -Repo owner/personal-project
```

### 2. Batch Process Multiple Repos

With git-ws:

```powershell
# All repos in workspace
git ws merge-bots
```

### 3. Scheduled Automation

Add to cron (Linux/macOS) or Task Scheduler (Windows):

```bash
# Daily at 2 AM
0 2 * * * cd /path/to/repo && /usr/local/bin/pwsh -File /path/to/git-merge-bots.ps1 merge
```

### 4. CI/CD Pipeline

```yaml
# GitHub Actions example
- name: Merge bot PRs
  run: |
    pwsh -File ./tools/git-merge-bots.ps1 merge --dry-run
```

## Comparison with Alternatives

| Feature           | git-merge-bots   | gh extension | GitHub Actions |
| ----------------- | ---------------- | ------------ | -------------- |
| Cross-platform    | ✅               | ✅           | ✅             |
| Multi-repo        | ✅ (with git-ws) | ❌           | ❌             |
| Local execution   | ✅               | ✅           | ❌             |
| PowerShell native | ✅               | ❌           | ❌             |
| Config-driven     | ✅               | ❌           | ✅             |
| Dry-run mode      | ✅               | ❌           | ❌             |

## Troubleshooting

**Error: "GitHub CLI (gh) not found"**

- Install: https://cli.github.com/

**Error: "GitHub CLI not authenticated"**

```bash
gh auth login
```

**Error: "Not in a git repository"**

```powershell
# Use -Repo flag
git-merge-bots list -Repo owner/repo
```

**No PRs found:**

- Check bot is enabled: `git-merge-bots config -Show`
- Verify bot user names in config
- Check PR author matches configured users

## Development

**Project structure:**

```
git-merge-bots/
├── git-merge-bots.psm1       # Main module
├── git-merge-bots.ps1        # CLI entry
├── git-merge-bots.cmd        # Windows shim
├── lib/
│   ├── config.ps1            # Configuration
│   ├── bots.ps1              # Bot detection
│   └── providers/
│       └── github.ps1        # GitHub provider
└── README.md
```

**Add new bot:**

1. Edit config: `git-merge-bots config -Edit`
2. Add bot with user array:

```json
{
  "bots": {
    "newbot": {
      "users": ["newbot[bot]"],
      "enabled": true
    }
  }
}
```

**Add new provider (GitLab, Azure DevOps):**

1. Create `lib/providers/gitlab.ps1`
2. Implement: `Get-BotPRs`, `Merge-PR`
3. Update main module to support provider selection

## Roadmap

- [ ] GitLab support
- [ ] Azure DevOps support
- [ ] PR filters (version semver, labels)
- [ ] Conflict resolution strategies
- [ ] Webhook/notification on merge
- [ ] Interactive mode (approve each PR)

## License

MIT License - See [LICENSE](../../LICENSE)

## Author

Marcel Körtgen ([@mkoertgen](https://github.com/mkoertgen))

Part of [scooped](https://github.com/mkoertgen/scooped) - Scoop bucket with PowerShell dev tools
