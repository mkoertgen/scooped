# git-ws

Git operations for VS Code workspace repositories.

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

## How it works

The tool reads the `folders` array from the `.code-workspace` JSON file
and performs git operations on each folder that contains a `.git` directory.
