# Host-specific profile for pwsh-L.exe
# This is loaded via POWERSHELL_PROFILE_DIRECTORY.
$startupScript = Join-Path $PSScriptRoot '..\pwsh-L.startup.ps1'
if (Test-Path $startupScript) {
    . $startupScript
}
