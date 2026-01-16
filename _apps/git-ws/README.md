# git-ws

Git operations for VS Code workspace repositories.

## The Problem

Working with multi-repo projects in VS Code workspaces means running `git pull`, `git status`, etc. in each repository manually. Tedious and error-prone.

## The Solution

`git-ws` (alias: `gws`) runs git commands across all repositories in a VS Code workspace file at once.

## Installation

```powershell
scoop bucket add mko https://github.com/mkoertgen/scooped
scoop install mko/git-ws
```

## Usage

```powershell
gws <command> [-Workspace <path>]
```

If no workspace is specified, the tool searches for `.code-workspace` files
in the current directory. If multiple are found, all are aggregated.

## Commands

| Command  | Description                                   |
| -------- | --------------------------------------------- |
| `pull`   | Fetch and pull --ff-only all repos            |
| `push`   | Push all repos with pending commits           |
| `fetch`  | Fetch all repos                               |
| `rebase` | Fetch and pull --rebase all repos             |
| `status` | Show git status (branch, dirty, ahead/behind) |
| `list`   | List all repos in workspace                   |
| `help`   | Show help                                     |

## Examples

```powershell
# Auto-detect workspace in current directory
gws pull

# Explicit workspace
gws pull -Workspace .\my.code-workspace

# Show status of all repos
gws status

# List repos from all workspaces in current dir
gws list
```

## How It Works

The tool reads the `folders` array from the `.code-workspace` JSON file
and performs git operations on each folder that contains a `.git` directory.

```json
{
  "folders": [
    { "path": "../repo-a" },
    { "path": "../repo-b" },
    { "path": "../shared-lib" }
  ]
}
```

```powershell
$ gws status
[>] repo-a
    main | clean | ✓ up to date
[>] repo-b
    feature/xyz | 2 modified | ↑1 ahead
[>] shared-lib
    main | clean | ✓ up to date
```

## Workspace Auto-Detection

When run without `-Workspace`, the tool automatically detects the correct workspace:

1. **Climb & Match**: Searches parent directories for `.code-workspace` files
2. **Folder Check**: Verifies which workspace contains the current directory
3. **Fallback**: Uses workspace files in current directory

This means you can run `gws pull` from anywhere inside a workspace folder structure.

## Development

For development and testing, add a wrapper function to your `$PROFILE`:

```powershell
function gwsdev {
  Import-Module "C:\path\to\git-ws.psm1" -Force
  Set-GitWorkspace @args
}
```

Test local changes without reinstalling:

```powershell
gwsdev status
gwsdev pull
gwsdev list
```
