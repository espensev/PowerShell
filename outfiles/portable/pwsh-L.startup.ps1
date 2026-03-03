# Startup script for pwsh-L.exe
# This is intentionally separate from the default Documents profile.

$global:PS1L_ProfileTag = 'PS-L'
$defaultStartDir = 'D:\DevTools\LocalTerminal\PS1-L'

function Test-PS1LAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

$global:PS1L_IsAdmin = Test-PS1LAdmin

# Keep caller directory when launched from a terminal.
# Only use the default path when starting in launcher dir/System32.
$currentDir = (Get-Location).ProviderPath
$launcherDir = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$shouldUseDefaultStart = ($currentDir -ieq $launcherDir)

if (-not $shouldUseDefaultStart -and $env:WINDIR) {
    $system32Dir = Join-Path $env:WINDIR 'System32'
    try {
        $resolvedSystem32 = (Resolve-Path -LiteralPath $system32Dir -ErrorAction Stop).ProviderPath
        $shouldUseDefaultStart = ($currentDir -ieq $resolvedSystem32)
    }
    catch {
        $shouldUseDefaultStart = $false
    }
}

if ($shouldUseDefaultStart) {
    if (-not (Test-Path -LiteralPath $defaultStartDir)) {
        $null = New-Item -ItemType Directory -Path $defaultStartDir -Force
    }

    Set-Location -LiteralPath $defaultStartDir
}

try {
    $titlePrefix = if ($global:PS1L_IsAdmin) { '[A]' } else { '' }
    $Host.UI.RawUI.WindowTitle = "$titlePrefix$($global:PS1L_ProfileTag)"
}
catch {
}

function global:prompt {
    $pathText = (Get-Location).Path.Replace($env:USERPROFILE, '~')
    $prefix = if ($global:PS1L_IsAdmin) { "[A]$($global:PS1L_ProfileTag)" } else { $global:PS1L_ProfileTag }
    $endChar = if ($global:PS1L_IsAdmin) { '#' } else { '>' }

    if ($PSStyle) {
        $prefixColor = if ($global:PS1L_IsAdmin) { $PSStyle.Foreground.BrightRed } else { $PSStyle.Foreground.BrightCyan }
        return "$prefixColor$prefix$($PSStyle.Reset) $pathText $endChar "
    }

    return "$prefix $pathText $endChar "
}
