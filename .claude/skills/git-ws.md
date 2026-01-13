# git-ws

A PowerShell utility for git operations across VS Code workspace repositories.

## Location

- Source: `_apps/git-ws/`
- Entry: `git-ws.ps1` / `git-ws.cmd`
- Module: `git-ws.psm1`
- Scoop manifest: `bucket/git-ws.json`
- Alias: `gws`

## Commands

| Command      | Description                                   |
| ------------ | --------------------------------------------- |
| `gws pull`   | Fetch and pull --ff-only all repos            |
| `gws push`   | Push all repos with pending commits           |
| `gws fetch`  | Fetch all repos                               |
| `gws rebase` | Fetch and pull --rebase all repos             |
| `gws status` | Show git status (branch, dirty, ahead/behind) |
| `gws list`   | List all repos in workspace                   |
| `gws help`   | Show help                                     |

## Usage

```powershell
# Auto-detect workspace in current directory
gws pull

# Explicit workspace file
gws pull -Workspace .\my.code-workspace

# Show status of all repos
gws status
```

## Features

- Auto-discovers `.code-workspace` files in current directory
- Aggregates multiple workspace files if found
- Only operates on folders containing `.git` directory
- Handles local-only repos (no remote) gracefully
- Color-coded output for status information

## Technical Details

- Reads `folders` array from `.code-workspace` JSON
- Resolves relative paths from workspace file location
- All git operations use `--prune` and `--quiet` flags
- Push only acts on repos with unpushed commits

## Development Notes

When modifying this tool:

- `CommandType` enum defines available commands
- `Find-WorkspaceFiles` discovers `.code-workspace` files
- `Get-WorkspaceFolders` parses workspace JSON and resolves paths
- Each git operation has dedicated function: `Invoke-GitFetch`, `Invoke-GitPull`, etc.
- Status tracking: `git rev-list --count "@{u}..HEAD"` for ahead, `"HEAD..@{u}"` for behind

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/git-ws
```
