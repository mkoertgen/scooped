using module ".\git-ws.psm1"
[CmdletBinding()]
param (
  [Parameter(Position = 0)][string]$Command = "help",
  [Parameter(Position = 1)][string]$Workspace
)

if ($Workspace) {
  gws $Command -Workspace $Workspace
} else {
  gws $Command
}
