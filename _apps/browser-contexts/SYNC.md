# Browser Contexts Sync

Synchronize your browser contexts, workspace files, and git repositories across multiple machines.

## Overview

The sync feature provides a `git push/pull`-like workflow for syncing your complete development environment:

- **Config**: All context definitions (browsers, URLs, bookmarks, workspaces)
- **Workspace files**: VS Code `.code-workspace` files
- **Git remotes**: Repository URLs for automatic cloning

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Meta-Repo (e.g., dotfiles)                                  │
├─────────────────────────────────────────────────────────────┤
│  .browser-contexts.json    ← Config + git-remotes metadata  │
│  ws-private.code-workspace ← Workspace definition           │
│  ws-work.code-workspace    ← Another workspace              │
└─────────────────────────────────────────────────────────────┘
                       ↓ git push/pull
                       ↓
┌─────────────────────────────────────────────────────────────┐
│ Machine 1                  │  Machine 2                     │
├────────────────────────────┼────────────────────────────────┤
│ bc push ~/dotfiles/...     │  bc pull ~/dotfiles/... --auto │
│                            │                                │
│ Exports:                   │  Imports:                      │
│  • Config                  │   • Config                     │
│  • Workspace files         │   • Workspace files            │
│  • Git remote URLs         │   • Clones missing repos       │
│                            │   • Pulls latest changes       │
└────────────────────────────┴────────────────────────────────┘
```

## Setup

> **Note:** `~` works in PowerShell on Windows (expands to `$HOME`, e.g., `C:\Users\username`)

### 1. Create Meta-Repo (One Time)

```powershell
# Create or use existing dotfiles repo
cd ~/dotfiles                    # or: cd C:\Users\username\dotfiles
git init
# or: git clone <your-dotfiles-repo>
```

### 2. Push from Source Machine

```powershell
# Export everything
bc push ~/dotfiles/.browser-contexts.json
# or: bc push C:\Users\username\dotfiles\.browser-contexts.json

# What happens:
# ✓ Exports config with git-remotes metadata
# ✓ Copies .code-workspace files to dotfiles/
# ✓ Shows git commit instructions

# Commit and push
cd ~/dotfiles
git add .browser-contexts.json *.code-workspace
git commit -m "Update browser-contexts"
git push
```

### 3. Pull on Target Machine

```powershell
# Clone dotfiles repo (if not already)
git clone <your-dotfiles-repo> ~/dotfiles

# Pull everything automatically
bc pull ~/dotfiles/.browser-contexts.json --auto

# What happens:
# 1. Pulls meta-repo (git pull --ff-only in ~/dotfiles)
# 2. Imports config → ~/.browser-contexts.json
# 3. Copies workspace files → C:\work\*.code-workspace
# 4. Clones missing repos → C:\work\private\planning, etc.
# 5. Updates git remotes
# 6. Pulls latest changes (git pull --ff-only)

# Interactive mode (prompts for each repo)
bc pull ~/dotfiles/.browser-contexts.json
```

## Commands

| Command                 | Description                                   |
| ----------------------- | --------------------------------------------- |
| `bc push <file>`        | Export config + workspace files + git-remotes |
| `bc pull <file>`        | Import config, prompt to clone missing repos  |
| `bc pull <file> --auto` | Import config, auto-clone and pull all repos  |

## Workflow Examples

### Daily Workflow (Machine 1 → Machine 2)

**Machine 1 (end of day):**
```powershell
bc push ~/dotfiles/.browser-contexts.json
cd ~/dotfiles
git add -A
git commit -m "Update contexts"
git push
```

**Machine 2 (start of day):**
```powershell
bc pull ~/dotfiles/.browser-contexts.json --auto
# ✓ Config updated
# ✓ Workspace files synced
# ✓ All repos cloned/updated
# Ready to work!
```

### New Machine Setup

```powershell
# 1. Clone dotfiles
git clone git@github.com:user/dotfiles.git ~/dotfiles

# 2. Pull everything
bc pull ~/dotfiles/.browser-contexts.json --auto

# 3. Done! All contexts, workspaces, and repos are ready
bc list
```

### Adding New Context

```powershell
# Create context with workspace
bc add myproject -w "C:\work\myproject.code-workspace"

# Push to sync
bc push ~/dotfiles/.browser-contexts.json
cd ~/dotfiles
git add -A; git commit -m "Add myproject context"; git push
```

## File Structure

### Meta-Repo Layout

```
~/dotfiles/
├── .browser-contexts.json      # Config + git-remotes
├── ws-private.code-workspace   # Workspace definitions
├── ws-work.code-workspace
└── .git/
```

### Config File Format

```json
{
  "dataDir": "C:\\Users\\user\\.browser-contexts",
  "contexts": {
    "myctx": {
      "browser": "chrome",
      "urls": ["https://example.com"],
      "workspace": "C:\\work\\ws-private.code-workspace"
    }
  },
  "gitRemotes": {
    "private/planning": {
      "origin": "https://github.com/user/planning.git"
    },
    "oss/mkoertgen/scooped": {
      "origin": "https://github.com/mkoertgen/scooped.git"
    }
  }
}
```

### Workspace File Example

```json
{
  "folders": [
    { "path": "private/planning" },
    { "path": "oss/mkoertgen/scooped" }
  ],
  "settings": {
    "terminal.integrated.defaultProfile.windows": "PowerShell"
  }
}
```

## How It Works

### Push Process

1. **Collect git remotes**: Scans all workspace folders for `.git` directories
2. **Export config**: Creates JSON with contexts + gitRemotes section
3. **Copy workspace files**: Copies `.code-workspace` files to meta-repo
4. **Ready to commit**: Shows git commands to commit changes

### Pull Process

1. **Pull meta-repo**: Runs `git pull --ff-only` in dotfiles repo
2. **Import config**: Loads contexts from JSON
3. **Sync workspace files**: Copies `.code-workspace` files if missing
4. **Restore repos**: For each repo in gitRemotes:
   - If missing: `git clone <origin> <path>`
   - If exists: Update remotes, optionally `git pull --ff-only`

### Git Remote Storage

- Paths are stored **relative to workspace base**
- Example: `private/planning` instead of `C:\work\private\planning`
- Makes config **portable across machines** with different base paths

## Advanced Usage

### Selective Sync

```powershell
# Interactive mode - choose what to clone
bc pull ~/dotfiles/.browser-contexts.json

# It prompts for each repo:
# Clone from https://github.com/user/repo.git? (y/n)
```

### Multiple Workspace Bases

```powershell
# Machine 1: C:\work\ws-private.code-workspace
# Machine 2: D:\dev\ws-private.code-workspace

# Both work! Just keep workspace files in same relative locations
```

### WSL Support

WSL workspaces are skipped during sync (remote workspaces managed separately).

## Troubleshooting

### Workspace files not copied

Ensure `.code-workspace` files exist locally before push:

```powershell
# Check workspace paths
bc show myctx

# Verify file exists
Test-Path "C:\work\ws-private.code-workspace"
```

### Clone fails

Check git remote URLs and credentials:

```powershell
# Verify remote URL
git ls-remote https://github.com/user/repo.git

# Use SSH if HTTPS fails
git remote set-url origin git@github.com:user/repo.git
```

### Pull doesn't update repos

Use `--auto` flag for automatic pull:

```powershell
bc pull ~/dotfiles/.browser-contexts.json --auto
```

## Security Considerations

### Private Repositories

The config stores **public git URLs**. For private repos:

1. Use SSH URLs (recommended): `git@github.com:user/private-repo.git`
2. Configure SSH keys on all machines
3. Or: Use HTTPS with credential manager

### Sensitive Data

**Never commit** to meta-repo:
- Browser profile data (`~/.browser-contexts/<name>/`)
- OAuth tokens
- Credentials

**Safe to commit**:
- Config file (`.browser-contexts.json`)
- Workspace files (`.code-workspace`)
- Git remote URLs (public or private with SSH)

### Dotfiles Repo Visibility

- **Public dotfiles**: OK if git remotes are public/SSH
- **Private dotfiles**: Recommended for work contexts

## Comparison

### vs. Manual Config Export/Import

| Feature           | export/import | push/pull |
| ----------------- | ------------- | --------- |
| Config sync       | ✓             | ✓         |
| Workspace files   | ✗             | ✓         |
| Git remotes       | ✗             | ✓         |
| Auto-clone repos  | ✗             | ✓         |
| Auto-pull updates | ✗             | ✓         |
| Git integration   | ✗             | ✓         |

### vs. Git Submodules

| Feature             | Submodules     | push/pull |
| ------------------- | -------------- | --------- |
| Setup complexity    | High           | Low       |
| Works with existing | Requires reset | ✓         |
| Selective cloning   | ✗              | ✓         |
| Multiple workspace  | Complex        | Simple    |

## Tips

### Automation

```powershell
# Add to profile for quick sync
function bcp { bc push ~/dotfiles/.browser-contexts.json; cd ~/dotfiles; git add -A; git commit -m "Update contexts"; git push }
function bcl { cd ~/dotfiles; git pull; bc pull ~/dotfiles/.browser-contexts.json --auto }
```

### Regular Sync

```powershell
# End of day
bcp

# Start of day
bcl
```

### Backup

The meta-repo IS your backup:

```powershell
# Push regularly
bc push ~/dotfiles/.browser-contexts.json
cd ~/dotfiles; git push

# Restore anywhere
git clone <dotfiles-repo>
bc pull ~/dotfiles/.browser-contexts.json --auto
```
