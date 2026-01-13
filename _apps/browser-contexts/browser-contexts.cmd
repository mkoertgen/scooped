@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0browser-contexts.ps1" %*
