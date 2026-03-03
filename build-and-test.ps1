[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'CodeCoverage', 'StaticAnalysis')]
    [string]$Configuration = 'Debug',

    [switch]$BootstrapDotnet,

    [switch]$SkipBuild,

    [switch]$SkipTests,

    [switch]$RunFullTests,

    [string]$SmokeTestPath = 'test/powershell/engine/OrderedHashtable.Tests.ps1',

    [switch]$NoClean,

    [string]$PublishDir = 'outfiles/portable',

    [switch]$NoCleanPublishDir,

    [string]$PortableExeName = 'pwsh-L.exe',

    [string]$PortableProfileTag = 'PS-L',

    [string]$PortableDefaultStartDir = 'D:\DevTools\LocalTerminal\PS1-L',

    [switch]$LaunchViaWindowsTerminal = $true,

    [string]$PortableWindowsTerminalPath = 'D:\Development\DesktopApps\Console\terminal\publish\terminal-shell-portable\WindowsTerminal.exe',

    [string]$PortableWindowsTerminalUserProfile = 'PS-L',

    [string]$PortableWindowsTerminalAdminProfile = 'PS-L Admin',

    [switch]$CreatePortableLauncher = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$publishRoot = if ([System.IO.Path]::IsPathRooted($PublishDir)) {
    $PublishDir
}
else {
    Join-Path $repoRoot $PublishDir
}

$buildOut = $publishRoot
$artifactsRoot = Join-Path $publishRoot '_artifacts'
$testOut = Join-Path $artifactsRoot 'test'
$logOut = Join-Path $artifactsRoot 'logs'

$buildLog = Join-Path $logOut 'build.log'
$pesterLog = Join-Path $logOut 'pester.log'
$pesterXml = Join-Path $testOut 'pester-results.xml'
$versionFile = Join-Path $logOut 'pwsh-version.txt'

if ((-not $NoCleanPublishDir) -and (Test-Path -Path $publishRoot)) {
    Remove-Item -Path $publishRoot -Recurse -Force
}

foreach ($dir in @($buildOut, $artifactsRoot, $testOut, $logOut)) {
    $null = New-Item -ItemType Directory -Path $dir -Force
}

Push-Location $repoRoot
try {
    Import-Module (Join-Path $repoRoot 'build.psm1') -Force

    if ($BootstrapDotnet) {
        Start-PSBootstrap -Scenario Dotnet
    }

    if (-not $SkipBuild) {
        $buildParams = @{
            UseNuGetOrg    = $true
            Output         = $buildOut
            Configuration  = $Configuration
            Verbose        = $true
        }

        if (-not $NoClean) {
            $buildParams['Clean'] = $true
        }

        Start-PSBuild @buildParams 2>&1 | Tee-Object -FilePath $buildLog
    }
    else {
        # Keep Start-PSPester aligned with custom outfiles location when skipping build.
        $options = New-PSOptions -Configuration $Configuration -Output $buildOut
        Set-PSOptions -Options $options
    }

    $pwshExe = Join-Path $buildOut 'pwsh.exe'
    if (-not (Test-Path -Path $pwshExe -PathType Leaf)) {
        throw "Build output not found: $pwshExe"
    }

    $portableExePath = $null
    if (-not [string]::IsNullOrWhiteSpace($PortableExeName)) {
        $portableExePath = Join-Path $buildOut $PortableExeName
        if ([System.IO.Path]::GetFileName($portableExePath) -ne 'pwsh.exe') {
            try {
                Copy-Item -Path $pwshExe -Destination $portableExePath -Force -ErrorAction Stop
            }
            catch {
                if (-not (Test-Path -Path $portableExePath -PathType Leaf)) {
                    throw "Portable exe alias was not created: $portableExePath"
                }

                Write-Warning "Could not overwrite '$portableExePath' (it may be running). Reusing existing file."
            }

            if (-not (Test-Path -Path $portableExePath -PathType Leaf)) {
                throw "Portable exe alias was not created: $portableExePath"
            }
        }
        else {
            $portableExePath = $pwshExe
        }
    }

    $pwshConfig = Join-Path $buildOut 'powershell.config.json'
    if (-not (Test-Path -Path $pwshConfig -PathType Leaf)) {
        throw "Expected publish config missing: $pwshConfig"
    }

    $portableCommand = $null
    $portableStartupScript = $null
    $portableProfileRoot = $null
    $portableProfileScript = $null
    if ($CreatePortableLauncher) {
        $startupExe = if ($portableExePath) { $portableExePath } else { $pwshExe }
        $startupExeName = [System.IO.Path]::GetFileName($startupExe)
        $startupBaseName = [System.IO.Path]::GetFileNameWithoutExtension($startupExe)

        $portableProfileRoot = Join-Path $buildOut 'profile'
        $null = New-Item -Path $portableProfileRoot -ItemType Directory -Force

        $portableStartupScript = Join-Path $buildOut "$startupBaseName.startup.ps1"
        if (-not (Test-Path -Path $portableStartupScript -PathType Leaf)) {
            $escapedPortableProfileTag = $PortableProfileTag.Replace("'", "''")
            $escapedPortableDefaultStartDir = $PortableDefaultStartDir.Replace("'", "''")
            $portableStartupTemplate = @'
# Startup script for __EXE__
# This is intentionally separate from the default Documents profile.

$global:PS1L_ProfileTag = '__PROFILE_TAG__'
$defaultStartDir = '__DEFAULT_START_DIR__'

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
'@

            $portableStartupContent = $portableStartupTemplate.Replace('__EXE__', $startupExeName)
            $portableStartupContent = $portableStartupContent.Replace('__PROFILE_TAG__', $escapedPortableProfileTag)
            $portableStartupContent = $portableStartupContent.Replace('__DEFAULT_START_DIR__', $escapedPortableDefaultStartDir)
            $portableStartupContent | Set-Content -Path $portableStartupScript -Encoding UTF8
        }

        $portableProfileScript = Join-Path $portableProfileRoot 'Microsoft.PowerShell_profile.ps1'
        if (-not (Test-Path -Path $portableProfileScript -PathType Leaf)) {
            $profileScriptTemplate = @'
# Host-specific profile for __EXE__
# This is loaded via POWERSHELL_PROFILE_DIRECTORY.
$startupScript = Join-Path $PSScriptRoot '..\__STARTUP__'
if (Test-Path $startupScript) {
    . $startupScript
}
'@
            $profileScriptContent = $profileScriptTemplate.Replace('__EXE__', $startupExeName).Replace('__STARTUP__', "$startupBaseName.startup.ps1")
            $profileScriptContent | Set-Content -Path $portableProfileScript -Encoding UTF8
        }

        $portableCommand = Join-Path $buildOut "$startupBaseName.cmd"
        $launchViaWindowsTerminalFlag = if ($LaunchViaWindowsTerminal) { '1' } else { '0' }
@"
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "_SCRIPT_DIR=%~dp0"
set "PSL_FORWARD_ARGS=%*"
set "POWERSHELL_PROFILE_DIRECTORY=%_SCRIPT_DIR%profile"
set "PSL_WT_ENABLED=$launchViaWindowsTerminalFlag"
set "PSL_WT_EXE=$PortableWindowsTerminalPath"
set "PSL_WT_PROFILE_USER=$PortableWindowsTerminalUserProfile"
set "PSL_WT_PROFILE_ADMIN=$PortableWindowsTerminalAdminProfile"

if /I "%PSL_WT_INTERNAL%"=="1" (
    goto :run_pwsh
)

if /I "%PSL_WT_ENABLED%"=="1" (
    if not defined WT_SESSION (
        if exist "%PSL_WT_EXE%" (
            set "PSL_WT_PROFILE=%PSL_WT_PROFILE_USER%"
            net session >nul 2>&1
            if "%ERRORLEVEL%"=="0" set "PSL_WT_PROFILE=%PSL_WT_PROFILE_ADMIN%"
            start "" "%PSL_WT_EXE%" new-tab -p "%PSL_WT_PROFILE%" cmd.exe /c "set PSL_WT_INTERNAL=1&&\"%~f0\" !PSL_FORWARD_ARGS!"
            exit /b %ERRORLEVEL%
        )
    )
)

:run_pwsh
"%_SCRIPT_DIR%$startupExeName" -NoLogo %*
"@ | Set-Content -Path $portableCommand -Encoding ASCII
    }

    (& $pwshExe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') |
        Set-Content -Path $versionFile -Force

    if (-not $SkipTests) {
        if ($RunFullTests) {
            $testPath = Join-Path $repoRoot 'test/powershell'
        }
        else {
            $smokePathCandidate = if ([System.IO.Path]::IsPathRooted($SmokeTestPath)) {
                $SmokeTestPath
            }
            else {
                Join-Path $repoRoot $SmokeTestPath
            }

            if (-not (Test-Path -Path $smokePathCandidate -PathType Leaf)) {
                throw "Smoke test path not found: $smokePathCandidate"
            }

            $testPath = (Resolve-Path $smokePathCandidate).ProviderPath
        }

        Start-PSPester `
            -Path $testPath `
            -BinDir $buildOut `
            -UseNuGetOrg `
            -OutputFile $pesterXml `
            -ThrowOnFailure `
            -Verbose 2>&1 | Tee-Object -FilePath $pesterLog
    }
}
finally {
    Pop-Location
}

Write-Host "Portable publish output: $buildOut"
Write-Host "Config file: $(Join-Path $buildOut 'powershell.config.json')"
if ($portableExePath) {
    Write-Host "Portable process executable: $portableExePath"
}
if ($portableCommand) {
    Write-Host "Portable launcher: $portableCommand"
}
if ($portableStartupScript) {
    Write-Host "Portable startup script: $portableStartupScript"
}
if ($portableProfileRoot) {
    Write-Host "Portable profile root: $portableProfileRoot"
}
if ($portableProfileScript) {
    Write-Host "Portable host profile: $portableProfileScript"
}
Write-Host "Logs: $logOut"
if (-not $SkipTests) {
    Write-Host "Pester results: $pesterXml"
}
Write-Host "Cleanup: remove '$buildOut'"
