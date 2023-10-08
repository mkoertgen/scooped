using module ".\phone-home.psm1"
[CmdletBinding()]
param ([Parameter()][string]$Command = "help")
ph $Command
