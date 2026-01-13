using module ".\browser-profiles.psm1"
[CmdletBinding()]
param (
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Args
)
Invoke-BrowserProfiles $Command $Args
