param (
    [switch]$Verbose,
    [switch]$WhatIf,
    [switch]$Dev,
    [switch]$CLI,
    [switch]$Silent,
    [switch]$Sysprep,
    [string]$LogPath,
    [string]$Language,
    [string]$User,
    [Alias('NoRestartExplorer')]
    [switch]$SkipExplorerRestart,
    [switch]$CreateRestorePoint,
    [switch]$SkipRegistryBackup,
    [switch]$RunDefaults,
    [switch]$RunDefaultsLite,
    [switch]$RunSavedSettings,
    [string]$Config,
    [string]$Apps,
    [string]$AppRemovalTarget,
    [switch]$RemoveApps,
    [switch]$RemoveGamingApps,
    [switch]$RemoveHPApps,
    [switch]$ForceRemoveEdge,
    [switch]$DisableDVR,
    [switch]$DisableGameBarIntegration,
    [switch]$EnableWindowsSandbox,
    [switch]$EnableWindowsSubsystemForLinux,
    [switch]$DisableTelemetry,
    [switch]$DisableFastStartup,
    [switch]$DisableBitlockerAutoEncryption,
    [switch]$DisableModernStandbyNetworking,
    [switch]$DisableNotifications,
    [switch]$DisableStorageSense,
    [switch]$DisableUpdateASAP,
    [switch]$PreventUpdateAutoReboot,
    [switch]$DisableDriverUpdates,
    [switch]$DisableDeliveryOptimization,
    [switch]$DisableDeviceAutoAppDownload,
    [switch]$DisableBing,
    [switch]$DisableStoreSearchSuggestions,
    [switch]$DisableDesktopSpotlight,
    [switch]$HideDesktopSpotlightIcon,
    [switch]$EnableDesktopSpotlight,
    [switch]$DisableLockscreenTips,
    [switch]$DisableSuggestions,
    [switch]$DisableLocationServices,
    [switch]$DisableFindMyDevice,
    [switch]$DisableEdgeAds,
    [switch]$DisableBraveBloat,
    [switch]$DisableSettings365Ads,
    [switch]$DisableSettingsHome,
    [switch]$ShowHiddenFolders,
    [switch]$ShowKnownFileExt,
    [switch]$HideDupliDrive,
    [switch]$EnableDarkMode,
    [switch]$DisableTransparency,
    [switch]$DisableAnimations,
    [switch]$TaskbarAlignLeft,
    [switch]$CombineTaskbarAlways, [switch]$CombineTaskbarWhenFull, [switch]$CombineTaskbarNever,
    [switch]$CombineMMTaskbarAlways, [switch]$CombineMMTaskbarWhenFull, [switch]$CombineMMTaskbarNever,
    [switch]$MMTaskbarModeAll, [switch]$MMTaskbarModeMainActive, [switch]$MMTaskbarModeActive,
    [switch]$HideSearchTb, [switch]$ShowSearchIconTb, [switch]$ShowSearchLabelTb, [switch]$ShowSearchBoxTb,
    [switch]$HideTaskview,
    [switch]$DisableStartRecommended,
    [switch]$DisableStartAllApps, [switch]$StartAllAppsCategory, [switch]$StartAllAppsGrid, [switch]$StartAllAppsList,
    [switch]$DisableStartPhoneLink,
    [switch]$DisableCopilot,
    [switch]$DisableRecall,
    [switch]$DisableClickToDo,
    [switch]$DisableAISvcAutoStart,
    [switch]$DisablePaintAI,
    [switch]$DisableNotepadAI,
    [switch]$DisableEdgeAI,
	[switch]$DisableChromeAI,
    [switch]$DisableWidgets,
    [switch]$HideChat,
    [switch]$EnableEndTask,
    [switch]$EnableLastActiveClick,
    [switch]$ClearStart,
    [string]$ReplaceStart,
    [switch]$ClearStartAllUsers,
    [string]$ReplaceStartAllUsers,
    [switch]$RevertContextMenu,
    [switch]$DisableMouseAcceleration,
    [switch]$DisableStickyKeys,
    [switch]$DisableWindowSnapping,
    [switch]$DisableSnapAssist,
    [switch]$DisableSnapLayouts,
    [switch]$HideTabsInAltTab, [switch]$Show3TabsInAltTab, [switch]$Show5TabsInAltTab, [switch]$Show20TabsInAltTab,
    [switch]$HideHome,
    [switch]$HideGallery,
    [switch]$ExplorerToHome,
    [switch]$ExplorerToThisPC,
    [switch]$ExplorerToDownloads,
    [switch]$ExplorerToOneDrive,
    [switch]$AddFoldersToThisPC,
    [switch]$HideOnedrive,
    [switch]$Hide3dObjects,
    [switch]$HideMusic,
    [switch]$HideIncludeInLibrary,
    [switch]$HideGiveAccessTo,
    [switch]$HideShare,
    [switch]$ShowDriveLettersFirst,
    [switch]$ShowDriveLettersLast,
    [switch]$ShowNetworkDriveLettersFirst,
    [switch]$HideDriveLetters,
    [switch]$RemoveWindowsDefender,
    [switch]$AcceptDefenderRemovalRisk,
    [switch]$VerifyDefenderRemoval
)

# This launcher is distributed on its own and downloads the project, so it can run with no
# Config/Languages folder anywhere near it. It lives inside the project tree too, though, so the
# localizer is read from there when available and every message falls back to its English source
# text otherwise - which is why the definition is inlined instead of dot-sourced.
$consoleLanguagesPath = Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Config') 'Languages'
$consoleLanguageCode = if ($Language) { $Language } else { [System.Globalization.CultureInfo]::CurrentUICulture.Name }

function Get-ConsoleText {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [object[]]$FormatArgs = $null
    )

    if (-not $script:ConsoleTextMap) {
        $script:ConsoleTextMap = @{}
        foreach ($code in @($consoleLanguageCode, 'en-US') | Select-Object -Unique) {
            $path = Join-Path (Join-Path $consoleLanguagesPath $code) 'Console.json'
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) { $script:ConsoleTextMap[$prop.Name] = [string]$prop.Value }
            break
        }
    }

    $resolved = if ($script:ConsoleTextMap.ContainsKey($Text)) { $script:ConsoleTextMap[$Text] } else { $Text }

    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        try { return $resolved -f $FormatArgs } catch { return $resolved }
    }

    return $resolved
}

# This is the localized fork, so the release it downloads is our own - that is where the language
# packs live. -Dev keeps upstream's original meaning of "the upstream development branch" for anyone
# who wants the English original.
$forkRepository = 'Swipa5fox/Win11Debloat-zh'

# Check if current PowerShell environment is limited by security policies
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Error (Get-ConsoleText "Win11Debloat is unable to run on your system, PowerShell execution is restricted by security policies")
    Write-Output (Get-ConsoleText "Press any key to exit...")
    $null = [System.Console]::ReadKey()
    Exit 1
}

Clear-Host
Write-Output "-------------------------------------------------------------------------------------------"
Write-Output (Get-ConsoleText " Win11Debloat Script")
Write-Output "-------------------------------------------------------------------------------------------"

$tempRootPath = $env:TEMP
$tempWorkPath = Join-Path $tempRootPath 'Win11Debloat'
$tempArchivePath = Join-Path $tempRootPath 'win11debloat.zip'

# Read the expected SHA-256 of a file from the text of a SHA256SUMS file (lines of "<64 hex digits>  <file name>", as
# written by sha256sum). Returns $null when the file is not listed.
function Get-ExpectedFileHash([string]$SumsText, [string]$FileName) {
    foreach ($line in ($SumsText -split "`r?`n")) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -ceq $FileName) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}

# Check a file against an expected SHA-256 value (hex digits, any case).
function Test-FileHashMatch([string]$Path, [string]$ExpectedHash) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ieq $ExpectedHash
}

# Names of the release assets the archive is verified with. When a release does not publish both, the source archive
# GitHub generates for the release is downloaded as before, without a checksum to compare it to.
$releaseArchiveName = 'Win11Debloat.zip'
$releaseChecksumsName = 'SHA256SUMS'
$expectedArchiveHash = $null

# Download Win11Debloat from GitHub as a zip archive.
try {
    if ($Dev) {
        Write-Output (Get-ConsoleText "> Downloading development version of Win11Debloat...")
        $sourceUri = "https://github.com/Raphire/Win11Debloat/archive/refs/heads/master.zip"
    }
    else {
        Write-Output (Get-ConsoleText "> Downloading Win11Debloat...")
        # This fork publishes its own releases; they carry the same Win11Debloat.zip plus SHA256SUMS
        # pair upstream ships, so the checksum below is verified against our build, not upstream's.
        $release = Invoke-RestMethod "https://api.github.com/repos/$forkRepository/releases/latest"
        $sourceUri = $release.zipball_url

        $archiveAsset = @($release.assets | Where-Object { $_.name -ceq $releaseArchiveName }) | Select-Object -First 1
        $checksumsAsset = @($release.assets | Where-Object { $_.name -ceq $releaseChecksumsName }) | Select-Object -First 1
        if ($archiveAsset -and $checksumsAsset) {
            $checksumsPath = Join-Path $tempRootPath 'win11debloat.sha256sums'
            Invoke-RestMethod $checksumsAsset.browser_download_url -OutFile $checksumsPath
            $expectedArchiveHash = Get-ExpectedFileHash ([System.IO.File]::ReadAllText($checksumsPath)) $releaseArchiveName
            Remove-Item $checksumsPath -Force
            if (-not $expectedArchiveHash) {
                throw "$releaseChecksumsName does not list $releaseArchiveName."
            }
            $sourceUri = $archiveAsset.browser_download_url
        }
        else {
            Write-Warning (Get-ConsoleText 'This release does not publish both Win11Debloat.zip and SHA256SUMS. Downloading the source archive without SHA-256 verification.')
        }
    }
    Invoke-RestMethod $sourceUri -OutFile $tempArchivePath
}
catch {
    Write-Host (Get-ConsoleText "Unable to fetch required files from GitHub. Please check your internet connection and try again.") -ForegroundColor Red
    Write-Error -ErrorRecord $_
    Write-Output ""
    Write-Output (Get-ConsoleText "Press enter to exit...")
    Read-Host | Out-Null
    Exit 1
}

# Do not use an archive that differs from the checksum published with the release
if ($expectedArchiveHash -and -not (Test-FileHashMatch $tempArchivePath $expectedArchiveHash)) {
    Remove-Item $tempArchivePath -Force
    Write-Host (Get-ConsoleText "The downloaded Win11Debloat archive does not match the SHA-256 checksum published with the release.") -ForegroundColor Red
    Write-Output ""
    Write-Output (Get-ConsoleText "Press enter to exit...")
    Read-Host | Out-Null
    Exit 1
}

# Remove old script folder if it exists, but keep configs, logs and backups
if (Test-Path $tempWorkPath) {
    Write-Output ""
    Write-Output (Get-ConsoleText "> Cleaning up old script files...")

    Get-ChildItem -Path $tempWorkPath -Exclude Config,Logs,Backups | Remove-Item -Recurse -Force
}

$configDir = Join-Path $tempWorkPath 'Config'
$backupDir = Join-Path $tempWorkPath 'ConfigOld'

# Temporarily move existing config files if they exist to prevent them from being overwritten by the new script files, will be moved back after the new script is unpacked
if (Test-Path "$configDir") {
    Write-Output ""
    Write-Output (Get-ConsoleText "> Backing up existing config files...")

    New-Item -ItemType Directory -Path "$backupDir" -Force | Out-Null

    $filesToKeep = @(
        'LastUsedSettings.json'
    )

    Get-ChildItem -Path "$configDir" -Recurse | Where-Object { $_.Name -in $filesToKeep } | Move-Item -Destination "$backupDir"

    Remove-Item "$configDir" -Recurse -Force
}

Write-Output ""
Write-Output (Get-ConsoleText "> Unpacking...")

# Unzip archive to Win11Debloat folder
Expand-Archive $tempArchivePath $tempWorkPath

# Remove archive
Remove-Item $tempArchivePath

# Move files
Get-ChildItem -Path (Join-Path $tempWorkPath '*Win11Debloat-*') -Recurse | Move-Item -Destination $tempWorkPath

# Add existing config files back to Config folder
if (Test-Path "$backupDir") {
    if (-not (Test-Path "$configDir")) {
        New-Item -ItemType Directory -Path "$configDir" -Force | Out-Null
    }

    Write-Output ""
    Write-Output (Get-ConsoleText "> Restoring existing config files...")

    Get-ChildItem -Path "$backupDir" -Recurse | Move-Item -Destination "$configDir"
    Remove-Item "$backupDir" -Recurse -Force
}

# Quote a value so it survives CommandLineToArgvW parsing in the child process: double any backslash run that
# precedes a quote or the closing quote, and escape embedded quotes, before wrapping the value in quotes.
function Format-LauncherArg([string]$Value) {
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

# Build the list of arguments to pass on to the script (excludes the -Dev switch, which only affects this launcher).
# Takes the bound parameters as input so it can be tested without running the launcher.
function Get-LauncherArgumentList([System.Collections.IDictionary]$BoundParameters) {
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        if ($entry.Key -eq 'Dev') { continue }

        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) {
                "-$($entry.Key)"
            }
        }
        else {
            "-$($entry.Key) $(Format-LauncherArg ([string]$entry.Value))"
        }
    }
}

$arguments = @(Get-LauncherArgumentList $PSBoundParameters)

Write-Output ""
Write-Output (Get-ConsoleText "> Launching Win11Debloat...")

# Minimize the PowerShell window when no parameters are provided
if ($arguments.Count -eq 0) {
    $windowStyle = "Minimized"
}
else {
    $windowStyle = "Normal"
}

# Remove PowerShell 7 modules from path to prevent module loading issues in the script
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $NewPSModulePath = $env:PSModulePath -split ';' | Where-Object -FilterScript { $_ -like '*WindowsPowerShell*' }
    $env:PSModulePath = $NewPSModulePath -join ';'
}

# Run Win11Debloat script with the provided arguments
$debloatScriptPath = Join-Path $tempWorkPath 'Win11Debloat.ps1'
$exitCode = 0
$debloatProcess = $null
try {
    $debloatProcess = Start-Process powershell.exe -WindowStyle $windowStyle -PassThru -ArgumentList "-executionpolicy bypass -File `"$debloatScriptPath`" $arguments" -Verb RunAs -ErrorAction Stop
}
catch {
    $exitCode = 1
    Write-Error (Get-ConsoleText "Failed to start Win11Debloat: {0}" -FormatArgs @($_))
}

# Wait for the process to finish before continuing
if ($null -ne $debloatProcess) {
    $debloatProcess.WaitForExit()
    $exitCode = $debloatProcess.ExitCode
}

# Remove all remaining script files, except for configs, logs and backups
if (Test-Path $tempWorkPath) {
    Write-Output ""
    Write-Output (Get-ConsoleText "> Cleaning up...")

    # Cleanup, remove Win11Debloat directory
    Get-ChildItem -Path $tempWorkPath -Exclude Config,Logs,Backups | Remove-Item -Recurse -Force
}

Write-Output ""
Exit $exitCode
