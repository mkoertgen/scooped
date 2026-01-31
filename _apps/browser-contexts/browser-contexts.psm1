# Browser Contexts - Isolated browser sessions with separate SSO/cookie/storage state
# Uses --user-data-dir for complete isolation (like Playwright)

$script:ConfigPath = Join-Path $env:USERPROFILE ".browser-contexts.json"
$script:DefaultDataDir = Join-Path $env:USERPROFILE ".browser-contexts"

# Windows API for window enumeration and control (needed for WSL VS Code windows)
if (-not ([System.Management.Automation.PSTypeName]'WindowControl').Type) {
  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowControl {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public const uint WM_CLOSE = 0x0010;
    private static List<KeyValuePair<IntPtr, string>> windows = new List<KeyValuePair<IntPtr, string>>();

    private static bool EnumCallback(IntPtr hWnd, IntPtr lParam) {
        if (IsWindowVisible(hWnd)) {
            StringBuilder sb = new StringBuilder(512);
            GetWindowText(hWnd, sb, 512);
            string title = sb.ToString();
            if (!string.IsNullOrEmpty(title) && title.Contains("Visual Studio Code")) {
                windows.Add(new KeyValuePair<IntPtr, string>(hWnd, title));
            }
        }
        return true;
    }

    public static List<KeyValuePair<IntPtr, string>> GetVSCodeWindows() {
        windows.Clear();
        EnumWindows(EnumCallback, IntPtr.Zero);
        return new List<KeyValuePair<IntPtr, string>>(windows);
    }

    public static bool CloseWindowByTitlePattern(string pattern) {
        windows.Clear();
        EnumWindows(EnumCallback, IntPtr.Zero);
        foreach (var w in windows) {
            if (w.Value.Contains(pattern)) {
                SendMessage(w.Key, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                return true;
            }
        }
        return false;
    }
}
"@
}

# Load library modules
. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\browser.ps1"
. "$PSScriptRoot\lib\bookmarks.ps1"
. "$PSScriptRoot\lib\context-mgmt.ps1"
. "$PSScriptRoot\lib\context-open.ps1"
. "$PSScriptRoot\lib\context-close.ps1"
. "$PSScriptRoot\lib\sync.ps1"

function Show-Help {
  Write-Host @"

browser-contexts - Isolated browser sessions with separate SSO/cookie/storage state

Usage: browser-contexts <command> [options]

Commands:
  list                         List all configured contexts
  show <context>               Show config for a specific context
  <context>                    Open a context (quick access)
  <context> <bookmark>         Open context with specific bookmark(s)
  open <context> [urls...]     Open context with optional extra URLs
  add <name> [-b browser] [-u urls] [-w workspace]  Add a new context
  remove <name> [-DeleteData]  Remove a context
  rename <old> <new> [-Force]  Rename a context (closes if running with -Force)
  urls <name> <url1> [url2...] Set URLs for a context (replaces all)
  add-url <name> <url>         Add URL to a context
  remove-url <name> <url>      Remove URL from a context
  bm <context>                 List bookmarks for a context
  bm <context> add <n> <url>   Add a named bookmark
  bm <context> remove <name>   Remove a bookmark
  workspace <name> <path>      Set VS Code workspace for a context
  remove-workspace <name>      Remove workspace from a context
  mkws <name> <dir1> [dir2...] Create .code-workspace from folders (optionally create context)
  ps                           Show running contexts
  close <context>              Close browser and VS Code for a context
  export                       Export config as JSON (pipe to file)
  import <file>                Import config from JSON file
  push <file>                  Export config with git-remotes (for sync)
  pull <file> [--auto] [--force] Import config and restore git-remotes (--auto clones/pulls, --force overwrites workspace files)
  config                       Show configuration and available browsers
  help                         Show this help

Options for 'add':
  -b, -Browser    Browser to use: chrome, edge, brave, firefox (optional for workspace-only)
  -u, -Urls       URLs to open automatically
  -w, -Workspace  Path to VS Code workspace (local or WSL remote)
  Note: Must have either -Browser or -Workspace (or both)

Workspace formats (must be .code-workspace files):
  C:\path\to\project.code-workspace              Local Windows workspace file
  wsl://Ubuntu/home/user/project.code-workspace  WSL remote workspace (shorthand)
  \\wsl$\Ubuntu\home\user\project.code-workspace WSL UNC workspace path

Examples:
  # Browser contexts
  browser-contexts add acme -b chrome
  browser-contexts add contoso -b chrome -u "https://portal.azure.com"

  # Browser + workspace
  browser-contexts add project -b chrome -w "C:\Projects\project.code-workspace"

  # Workspace-only (no browser) - for backend/infra projects
  browser-contexts add infra -w "C:\Projects\infrastructure.code-workspace"
  browser-contexts add docs -w "wsl://Ubuntu/home/user/docs.code-workspace"

  # Create workspace from multiple folders
  browser-contexts mkws infra ./terraform ./ansible ./scripts
  browser-contexts mkws api ./src ./tests ./docs -CreateContext

  browser-contexts workspace acme "wsl://Ubuntu/home/user/acme.code-workspace"
  browser-contexts urls acme "https://dev.azure.com/acme" "https://teams.microsoft.com"
  browser-contexts bm acme add azure https://portal.azure.com
  browser-contexts bm acme                    # List bookmarks
  browser-contexts acme                       # Quick access (opens browser + workspace)
  browser-contexts acme azure                 # Open with bookmark 'azure'
  browser-contexts open acme https://...      # With extra URL
  browser-contexts remove old-context -DeleteData

How it works:
  Each context gets its own browser data directory (~/.browser-contexts/<name>/).
  This provides complete isolation: cookies, localStorage, SSO sessions, extensions.
  Like Playwright's browser contexts, but for manual browsing.

Config: ~/.browser-contexts.json

"@ -ForegroundColor Cyan
}

function Invoke-BrowserContexts {
  param (
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Arguments,
    [Alias("b")][string]$Browser = "chrome",
    [Alias("u")][string[]]$Urls,
    [Alias("w")][string]$Workspace,
    [switch]$DeleteData
  )

  switch ($Command.ToLower()) {
    "help" { Show-Help }
    "list" { Show-Contexts }
    "ps" { Show-RunningContexts }
    { $_ -in "close", "kill" } {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts close <context>"
        return
      }
      Stop-Context -ContextName $Arguments[0] -Force
    }
    "config" { Show-Config }
    "show" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts show <context>"
        return
      }
      Show-ContextDetail -ContextName $Arguments[0]
    }
    { $_ -in "bm", "bookmark", "bookmarks" } {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts bm <context> [add|remove <name> [url]]"
        return
      }
      $ctxName = $Arguments[0]
      if ($Arguments.Count -eq 1) {
        # Just show bookmarks
        Show-Bookmarks -ContextName $ctxName
      } elseif ($Arguments[1] -eq "add" -and $Arguments.Count -ge 4) {
        Add-Bookmark -ContextName $ctxName -BookmarkName $Arguments[2] -Url $Arguments[3]
      } elseif ($Arguments[1] -eq "remove" -and $Arguments.Count -ge 3) {
        Remove-Bookmark -ContextName $ctxName -BookmarkName $Arguments[2]
      } else {
        Write-Error "Usage: browser-contexts bm <context> [add <name> <url> | remove <name>]"
      }
    }
    "export" { Export-ContextConfig }
    "import" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts import <file.json>"
        return
      }
      Import-ContextConfig -Path $Arguments[0]
    }
    "add" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts add <name> [-b browser] [-u urls] [-w workspace]"
        return
      }
      $params = @{
        ContextName = $Arguments[0]
        Browser     = $Browser
      }
      if ($Urls) { $params.Urls = $Urls }
      if ($Workspace) { $params.Workspace = $Workspace }
      Add-Context @params
    }
    "remove" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts remove <name> [-DeleteData]"
        return
      }
      Remove-Context -ContextName $Arguments[0] -DeleteData:$DeleteData
    }
    "rename" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts rename <oldname> <newname> [-Force]"
        return
      }
      $forceRename = $Arguments -contains "-Force" -or $Arguments -contains "-f"
      Rename-Context -OldName $Arguments[0] -NewName $Arguments[1] -Force:$forceRename
    }
    "urls" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts urls <name> <url1> [url2...]"
        return
      }
      Set-ContextUrls -ContextName $Arguments[0] -Urls $Arguments[1..($Arguments.Count - 1)]
    }
    "add-url" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts add-url <name> <url>"
        return
      }
      Add-ContextUrl -ContextName $Arguments[0] -Urls $Arguments[1..($Arguments.Count - 1)]
    }
    "remove-url" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts remove-url <name> <url>"
        return
      }
      Remove-ContextUrl -ContextName $Arguments[0] -Url $Arguments[1]
    }
    "workspace" {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts workspace <name> <workspace-path>"
        return
      }
      Set-ContextWorkspace -ContextName $Arguments[0] -WorkspacePath $Arguments[1]
    }
    "remove-workspace" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts remove-workspace <name>"
        return
      }
      Remove-ContextWorkspace -ContextName $Arguments[0]
    }
    { $_ -in "mkws", "create-workspace", "new-workspace" } {
      if (-not $Arguments -or $Arguments.Count -lt 2) {
        Write-Error "Usage: browser-contexts mkws <name> <dir1> [dir2...] [-CreateContext]"
        return
      }
      $createCtx = $Arguments -contains "-CreateContext" -or $Arguments -contains "-c"
      $folders = $Arguments[1..($Arguments.Count - 1)] | Where-Object { $_ -notmatch "^-" }
      New-WorkspaceFile -Name $Arguments[0] -Folders $folders -CreateContext:$createCtx
    }
    "open" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts open <name> [urls...]"
        return
      }
      $extraUrls = if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count - 1)] } else { @() }
      Open-Context -ContextName $Arguments[0] -ExtraUrls $extraUrls
    }
    "push" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts push <file>"
        return
      }
      Push-ContextConfig -Path $Arguments[0]
    }
    "pull" {
      if (-not $Arguments -or $Arguments.Count -eq 0) {
        Write-Error "Usage: browser-contexts pull <file> [--auto] [--force]"
        return
      }
      $autoClone = $Arguments -contains "--auto" -or $Arguments -contains "-a"
      $force = $Arguments -contains "--force" -or $Arguments -contains "-f"
      Pull-ContextConfig -Path $Arguments[0] -AutoClone:$autoClone -Force:$force
    }
    default {
      # Treat unknown command as context name for quick access
      $config = Get-Config
      if ($config.contexts.PSObject.Properties.Name -contains $Command) {
        Open-Context -ContextName $Command -ExtraUrls $Arguments
      } else {
        Write-Error "Unknown command or context: '$Command'. Use 'help' for usage."
      }
    }
  }
}

Export-ModuleMember -Function Invoke-BrowserContexts
