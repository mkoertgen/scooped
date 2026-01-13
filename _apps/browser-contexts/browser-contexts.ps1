#!/usr/bin/env pwsh
# Browser Contexts - Isolated browser sessions
# See README.md for usage

$modulePath = Join-Path $PSScriptRoot "browser-contexts.psm1"
Import-Module $modulePath -Force

Invoke-BrowserContexts @args
