<#
    .SYNOPSIS
    Restarts Windows Explorer to apply system changes.

    .DESCRIPTION
    Restarts the Explorer process to ensure all UI modifications take effect. Shows a warning if any of the applied features require a reboot to take full effect.
#>
function Invoke-RestartExplorer {
    if ($script:Params.ContainsKey("WhatIf")) {
        Write-Host (Get-ConsoleText "[WhatIf] Restart the Windows Explorer process") -ForegroundColor Cyan
        return
    }

    Write-Host (Get-ConsoleText "> Attempting to restart the Windows Explorer process to apply all changes...")

    if ($script:Params.ContainsKey('SkipExplorerRestart')) {
        Write-Host (Get-ConsoleText "Explorer process restart was skipped, please manually reboot your PC to apply all changes") -ForegroundColor Yellow
        return
    }

    $rebootFeatures = Get-RebootFeatureLabels
    foreach ($displayLabel in $rebootFeatures) {
        Write-Host (Get-ConsoleText "Warning: '{0}' requires a reboot to take full effect" -FormatArgs @($displayLabel)) -ForegroundColor Yellow
    }

    # Only restart if the PowerShell process matches the OS architecture.
    # Restarting explorer from a 32bit PowerShell window will fail on a 64bit OS
    if ([Environment]::Is64BitProcess -eq [Environment]::Is64BitOperatingSystem) {
        Write-Host (Get-ConsoleText "Restarting the Windows Explorer process... (This may cause your screen to flicker)")
        Stop-Process -processName: Explorer -Force
    }
    else {
        Write-Host (Get-ConsoleText "Unable to restart Windows Explorer process, please manually reboot your PC to apply all changes") -ForegroundColor Yellow
    }
}
