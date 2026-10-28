<#
    .SYNOPSIS
        Tests whether the current process is elevated.

    .DESCRIPTION
        Split out from Get-DefenderRemovalPreflight so the elevation branch can be exercised by tests
        without an elevated host.

    .OUTPUTS
        System.Boolean
#>
function Test-DefenderRemovalIsAdmin {
    return ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


<#
    .SYNOPSIS
        Checks whether Microsoft Defender Antivirus is installed and whether its removal is currently
        safe to attempt.

    .DESCRIPTION
        Windows client has no "Windows-Defender" optional feature since 1803, so there is nothing to
        uninstall through DISM. Removal means deleting service registrations, filter/ELAM drivers,
        policy keys, scheduled tasks and program data - all of which Microsoft protects while tamper
        protection is on. This function reports every precondition the removal depends on so the caller
        can block early with a useful message instead of half-deleting a security product.

    .OUTPUTS
        PSCustomObject with IsAdmin, DefenderPresent, TamperProtected, ThirdPartyAntivirus, IsUnprotected
        and Blockers.
#>
function Get-DefenderRemovalPreflight {
    $isAdmin = Test-DefenderRemovalIsAdmin

    $service = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
    $serviceKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend'
    $programFolder = Join-Path $env:ProgramFiles 'Windows Defender'
    $defenderPresent = ($null -ne $service) -or (Test-Path -LiteralPath $serviceKey) -or (Test-Path -LiteralPath $programFolder)

    $tamperProtected = Test-DefenderTamperProtection
    $thirdParty = @(Get-DefenderThirdPartyAntivirus)

    $blockers = @()
    if (-not $isAdmin) {
        $blockers += (Get-ConsoleText "administrator rights are required")
    }
    if (-not $defenderPresent) {
        $blockers += (Get-ConsoleText "Microsoft Defender Antivirus is not present")
    }
    if ($tamperProtected) {
        $blockers += (Get-ConsoleText "tamper protection is on - turn it off in Windows Security first")
    }

    return [PSCustomObject]@{
        IsAdmin             = $isAdmin
        DefenderPresent     = $defenderPresent
        TamperProtected     = $tamperProtected
        ThirdPartyAntivirus = $thirdParty
        IsUnprotected       = ($thirdParty.Count -eq 0)
        Blockers            = $blockers
    }
}


<#
    .SYNOPSIS
        Returns the display names of antivirus products registered by something other than Microsoft
        Defender.

    .DESCRIPTION
        root\SecurityCenter2 is the list Windows Security shows to the user. Anything in there that is
        not Defender means the machine keeps an on-access scanner after Defender is gone, which is the
        only situation where removing Defender does not leave the system unprotected.

    .OUTPUTS
        System.String[]
#>
function Get-DefenderThirdPartyAntivirus {
    $products = @()
    try {
        $instances = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($instance in $instances) {
            $name = [string]$instance.displayName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($name -match '(?i)microsoft defender|windows defender') { continue }
            $products += $name
        }
    }
    catch { }

    return $products
}


<#
    .SYNOPSIS
        Tests whether Defender tamper protection is currently on.

    .DESCRIPTION
        Tamper protection blocks registry and service changes to Defender, so a removal attempted while
        it is on silently does nothing. Get-MpComputerStatus is the authoritative source; if Defender is
        already stopped far enough that the cmdlet is unavailable, fall back to the registry value the
        Windows Security UI writes (5 = on).

    .OUTPUTS
        System.Boolean
#>
function Test-DefenderTamperProtection {
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        return [bool]$status.IsTamperProtected
    }
    catch { }

    try {
        $features = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' -Name 'TamperProtection' -ErrorAction Stop
        return ([int]$features.TamperProtection -eq 5)
    }
    catch {
        return $false
    }
}


<#
    .SYNOPSIS
        Removes a registry key, falling back to a SYSTEM context when the key is ACL-protected.

    .DESCRIPTION
        Service keys under HKLM\SYSTEM\CurrentControlSet\Services are owned by TrustedInstaller and
        Defender's own keys are protected while tamper protection is on. When the elevated caller still
        cannot delete a key, the delete is replayed through a one-shot scheduled task running as SYSTEM,
        which is the least invasive way to get the required token without shipping a native helper.
        The temporary task and script are always cleaned up.

    .OUTPUTS
        System.Boolean. $true when the key no longer exists.
#>
function Remove-DefenderRegistryKey {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $Key)) { return $true }

    try {
        Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $Key)) { return $true }
    }
    catch { }

    return (Invoke-SystemRegistryDelete -Key $Key)
}


<#
    .SYNOPSIS
        Deletes a single registry key from a one-shot task running as SYSTEM.

    .OUTPUTS
        System.Boolean. $true when the key no longer exists.
#>
function Invoke-SystemRegistryDelete {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $taskName = 'Win11DebloatDefenderCleanup'
    $stamp = [Guid]::NewGuid().ToString('N')
    $scriptPath = Join-Path $env:TEMP "Win11DebloatDefenderCleanup-$stamp.cmd"
    $logPath = Join-Path $env:TEMP "Win11DebloatDefenderCleanup-$stamp.log"

    try {
        $quotedKey = $Key.Replace('"', '""')
        $lines = @(
            '@echo off',
            "reg delete `"$quotedKey`" /f >> `"$logPath`" 2>&1",
            'exit /b %errorlevel%'
        )
        Set-Content -LiteralPath $scriptPath -Value $lines -Encoding ASCII -Force

        & schtasks.exe /create /tn $taskName /tr "cmd.exe /c `"$scriptPath`"" /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
        & schtasks.exe /run /tn $taskName 2>&1 | Out-Null

        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            Start-Sleep -Milliseconds 500
            if (-not (Test-Path -LiteralPath $Key)) { break }
        }
    }
    catch { }
    finally {
        & schtasks.exe /delete /tn $taskName /f 2>&1 | Out-Null
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    return (-not (Test-Path -LiteralPath $Key))
}


<#
    .SYNOPSIS
        Deletes a Defender program folder after taking ownership from TrustedInstaller.

    .OUTPUTS
        System.Boolean. $true when the folder no longer exists.
#>
function Remove-DefenderFolder {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    # takeown/icacls ship with Windows, so no extra dependency. The well-known Administrators SID is
    # used instead of a localized group name, which would break on non-English systems.
    & takeown.exe /f $Path /r /d y 2>&1 | Out-Null
    & icacls.exe $Path /grant '*S-1-5-32-544:(OI)(CI)F' /t /c 2>&1 | Out-Null

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch { }

    return (-not (Test-Path -LiteralPath $Path))
}


<#
    .SYNOPSIS
        Permanently removes Microsoft Defender Antivirus from the machine.

    .DESCRIPTION
        Unsupported by Microsoft. On Windows client there is no optional feature to uninstall, so this
        deletes the service registrations (WinDefend, WdNisSvc, Sense, SecurityHealthService), the
        filter and ELAM drivers (WdFilter, WdNisDrv, WdBoot), Defender's policy and configuration keys,
        its scheduled tasks, and the program/data folders. The removal cannot be undone from this tool:
        recovery requires an in-place upgrade or a clean install, and a Windows feature upgrade brings
        Defender back.

        Registry keys are exported and, when available, a system restore point is created first.

    .OUTPUTS
        System.Boolean. $true when Defender's service registration is gone afterwards.
#>
function Invoke-RemoveWindowsDefender {
    $whatIf = $script:Params.ContainsKey('WhatIf')

    $preflight = Get-DefenderRemovalPreflight
    if ($preflight.Blockers.Count -gt 0) {
        foreach ($blocker in $preflight.Blockers) {
            Write-Warning (Get-ConsoleText "Cannot remove Microsoft Defender Antivirus: {0}" -FormatArgs @($blocker))
        }
        return $false
    }

    # Every service entry Defender registers. WdFilter/WdNisDrv are file-system filter drivers and
    # WdBoot is the early-launch driver; deleting the service entry before the driver file is what
    # keeps Windows from booting with a start driver whose file is missing.
    $services = @('WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'WdFilter', 'WdNisDrv', 'WdBoot', 'webthreatdefsvc', 'webthreatdefusersvc')
    $serviceKeys = @($services | ForEach-Object { "HKLM:\SYSTEM\CurrentControlSet\Services\$_" })
    $configKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center'
    )
    $driverFiles = @('WdFilter.sys', 'WdNisDrv.sys', 'WdBoot.sys') | ForEach-Object { Join-Path $env:SystemRoot "System32\drivers\$_" }
    $folders = @(
        (Join-Path $env:ProgramFiles 'Windows Defender'),
        (Join-Path $env:ProgramFiles 'Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Support'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Security Health')
    )

    if ($whatIf) {
        Write-Host (Get-ConsoleText "[WhatIf] Remove Microsoft Defender Antivirus") -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Stop and delete services: {0}" -FormatArgs @(($services -join ', '))) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete registry keys: {0}" -FormatArgs @((($serviceKeys + $configKeys) -join ', '))) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete driver files: {0}" -FormatArgs @(($driverFiles -join ', '))) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete folders: {0}" -FormatArgs @(($folders -join ', '))) -ForegroundColor Cyan
        return $true
    }

    # ---- Phase 1: back out safely ----
    Write-Host (Get-ConsoleText "> Backing up Defender registry keys...")
    $backupRoot = Join-Path $script:RegistryBackupsPath ("DefenderRemoval-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        $backupTargets = [ordered]@{
            'WinDefend'       = 'HKLM\SYSTEM\CurrentControlSet\Services\WinDefend'
            'WdFilter'        = 'HKLM\SYSTEM\CurrentControlSet\Services\WdFilter'
            'WdNisDrv'        = 'HKLM\SYSTEM\CurrentControlSet\Services\WdNisDrv'
            'WdBoot'          = 'HKLM\SYSTEM\CurrentControlSet\Services\WdBoot'
            'DefenderConfig'  = 'HKLM\SOFTWARE\Microsoft\Windows Defender'
            'DefenderPolicy'  = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'
        }
        foreach ($name in $backupTargets.Keys) {
            $target = $backupTargets[$name]
            if (-not (Test-Path -LiteralPath $target)) { continue }
            & reg.exe export $target (Join-Path $backupRoot "$name.reg") /y 2>&1 | Out-Null
        }
        Write-Host (Get-ConsoleText "Backup written to {0}" -FormatArgs @($backupRoot))
    }
    catch {
        Write-Warning (Get-ConsoleText "Failed to export the Defender registry keys, continuing anyway: {0}" -FormatArgs @($_.Exception.Message))
    }

    # A restore point cannot bring back a deleted security product, but it does cover collateral
    # changes, so it is worth the minute it takes.
    if (Get-Command Invoke-SystemRestorePoint -ErrorAction SilentlyContinue) {
        Write-Host (Get-ConsoleText "> Creating a system restore point before removal...")
        if (-not (Invoke-SystemRestorePoint)) {
            Write-Warning (Get-ConsoleText "System restore point could not be created. Continuing with the removal.")
        }
    }

    # ---- Phase 2: stop everything that holds the driver files open ----
    Write-Host (Get-ConsoleText "> Stopping Defender services...")
    foreach ($serviceName in $services) {
        & sc.exe stop $serviceName 2>&1 | Out-Null
    }
    Get-Process -Name 'MsMpEng', 'NisSrv', 'MpDefenderCoreService', 'SecurityHealthService', 'SecurityHealthSystray' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    # ---- Phase 3: scheduled tasks ----
    Write-Host (Get-ConsoleText "> Removing Defender scheduled tasks...")
    try {
        Get-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\*' -ErrorAction SilentlyContinue |
            Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defender\*' -ErrorAction SilentlyContinue |
            Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch { }

    # ---- Phase 4: service registrations, then the driver files ----
    $failedServices = @()
    foreach ($serviceKey in $serviceKeys) {
        if (-not (Remove-DefenderRegistryKey -Key $serviceKey)) {
            $failedServices += ($serviceKey -split '\\')[-1]
        }
    }

    Write-Host (Get-ConsoleText "> Deleting Defender driver files...")
    foreach ($driverFile in $driverFiles) {
        if (-not (Test-Path -LiteralPath $driverFile)) { continue }
        & takeown.exe /f $driverFile 2>&1 | Out-Null
        & icacls.exe $driverFile /grant '*S-1-5-32-544:F' 2>&1 | Out-Null
        Remove-Item -LiteralPath $driverFile -Force -ErrorAction SilentlyContinue
    }

    # ---- Phase 5: configuration and policy keys ----
    Write-Host (Get-ConsoleText "> Deleting Defender registry keys...")
    $failedKeys = @()
    foreach ($configKey in $configKeys) {
        if (-not (Remove-DefenderRegistryKey -Key $configKey)) {
            $failedKeys += $configKey
        }
    }

    # SecurityHealth autostart entry (Windows Security tray icon)
    $runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path -LiteralPath $runKey) {
        Remove-ItemProperty -Path $runKey -Name 'SecurityHealth' -Force -ErrorAction SilentlyContinue
    }

    # ---- Phase 6: program folders ----
    Write-Host (Get-ConsoleText "> Deleting Defender program folders...")
    $failedFolders = @()
    foreach ($folder in $folders) {
        if (-not (Remove-DefenderFolder -Path $folder)) {
            $failedFolders += $folder
        }
    }

    # ---- Report ----
    $serviceGone = -not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend')
    $serviceStillListed = $null -ne (Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue)

    if ($serviceGone -and -not $serviceStillListed) {
        Write-Host (Get-ConsoleText "Microsoft Defender Antivirus was removed. Restart Windows to finish cleaning up.") -ForegroundColor Green
    }
    else {
        Write-Warning (Get-ConsoleText "Microsoft Defender Antivirus could not be fully removed. Restart Windows and run the removal again.")
    }

    if ($failedServices.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These service registrations could not be deleted: {0}" -FormatArgs @(($failedServices -join ', ')))
    }
    if ($failedKeys.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These registry keys could not be deleted: {0}" -FormatArgs @(($failedKeys -join ', ')))
    }
    if ($failedFolders.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These folders could not be deleted: {0}" -FormatArgs @(($failedFolders -join ', ')))
    }

    return ($serviceGone -and -not $serviceStillListed)
}
