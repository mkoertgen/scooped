#!/usr/bin/env pwsh
# git-merge-bots CLI entry point
# Cross-platform: Works on Windows (PS 5.1+) and Unix (pwsh)

$ErrorActionPreference = 'Stop'

# Import module from same directory
$modulePath = Join-Path $PSScriptRoot 'git-merge-bots.psm1'
Import-Module $modulePath -Force

# Pass all arguments to main function
Invoke-GitMergeBots @args
