@echo off
REM Windows CMD shim for git-merge-bots
REM Scoop will create this automatically, but we provide it for manual installation

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-merge-bots.ps1" %*
