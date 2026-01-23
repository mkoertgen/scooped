# Close contexts and list running contexts

function Get-RunningContexts {
    $config = Get-Config
    $running = @()

    # Check each context with fast lockfile detection
    foreach ($ctxName in $config.contexts.PSObject.Properties.Name) {
        $ctx = $config.contexts.$ctxName
        $dataDir = Get-ContextDataDir $ctxName
        $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }

        # Check if browser is running (fast lockfile check)
        if (Test-ContextRunning -Browser $browser -DataDir $dataDir) {
            $running += [PSCustomObject]@{
                Context = $ctxName
                Type    = "browser"
                Name    = $browser
            }
        }

        # Check if VS Code is running for this workspace
        if ($ctx.workspace) {
            $wsName = [System.IO.Path]::GetFileNameWithoutExtension($ctx.workspace)
            $vsCodeWindows = [WindowControl]::GetVSCodeWindows()
            foreach ($window in $vsCodeWindows) {
                $title = $window.Value
                if ($title -match "- $([regex]::Escape($wsName)) \(Workspace\)") {
                    $running += [PSCustomObject]@{
                        Context = $ctxName
                        Type    = "vscode"
                        Name    = "VS Code"
                        Title   = $title -replace ' - Visual Studio Code$', ''
                    }
                    break
                }
            }
        }
    }

    return $running
}

function Show-RunningContexts {
    $running = Get-RunningContexts

    Write-Host "`nRunning Contexts:" -ForegroundColor Cyan
    Write-Host "-----------------"

    if ($running.Count -eq 0) {
        Write-Host "  No contexts currently running." -ForegroundColor DarkGray
    } else {
        # Group by context
        $grouped = $running | Group-Object Context
        foreach ($group in $grouped) {
            Write-Host "  $($group.Name)" -ForegroundColor Green
            foreach ($item in $group.Group) {
                if ($item.Type -eq 'browser') {
                    Write-Host "    browser: $($item.Name)" -ForegroundColor DarkGray
                } elseif ($item.Type -eq 'vscode') {
                    Write-Host "    vscode:  $($item.Title)" -ForegroundColor Magenta
                }
            }
        }
    }
    Write-Host ""
}

function Stop-Context {
    param (
        [Parameter(Mandatory)][string]$ContextName,
        [switch]$Force
    )

    $config = Get-Config
    $ctx = $config.contexts.$ContextName
    $closed = $false

    # Close VS Code first (fast window enumeration)
    if ($ctx -and $ctx.workspace) {
        $workspacePath = $ctx.workspace
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($workspacePath)
        $basename = Get-WorkspaceBasename $expandedPath

        if (Close-VSCodeWindow -WorkspaceBasename $basename) {
            $closed = $true
        }
    }

    # Then close browser (may be slower if modal/alert is open)
    $dataDir = Get-ContextDataDir $ContextName
    $browser = if ($ctx.browser) { $ctx.browser } else { "chrome" }
    $isRunning = Test-ContextRunning -Browser $browser -DataDir $dataDir

    if ($isRunning) {
        # Find and close browser process
        $processName = switch ($browser) {
            "firefox" { "firefox" }
            "edge" { "msedge" }
            "brave" { "brave" }
            default { "chrome" }
        }

        $escapedPath = [regex]::Escape($dataDir)
        $proc = Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -and $cmdLine -match $escapedPath -and $cmdLine -notlike "*--type=*"
        } | Select-Object -First 1

        if ($proc) {
            Stop-Process -Id $proc.Id -Force:$Force
            Write-Host "Closed browser ($processName, PID $($proc.Id))" -ForegroundColor Green
            $closed = $true

            # Clean up Firefox lock file
            if ($browser -eq "firefox") {
                $lockFile = Join-Path $dataDir "parent.lock"
                if (Test-Path $lockFile) {
                    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    Write-Host "Cleaned up Firefox lock file" -ForegroundColor DarkGray
                }
            }
        }
    }

    if (-not $closed) {
        Write-Host "Context '$ContextName' is not running." -ForegroundColor Yellow
    }
}
