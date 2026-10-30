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
    $installed = ($null -ne $service) -or (Test-Path -LiteralPath $serviceKey) -or (Test-Path -LiteralPath $programFolder)

    # A previous run can stop halfway - services gone, folders and keys left behind. Judging presence by
    # the service alone would then refuse to clean up exactly the leftovers a retry is meant to finish,
    # so any Defender trace on the machine counts as present.
    $residue = @()
    if (-not $installed) {
        $residue = @(Get-DefenderResidue)
    }
    $defenderPresent = $installed -or ($residue.Count -gt 0)

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
        Installed           = $installed
        ResidueOnly         = ($defenderPresent -and -not $installed)
        Residue             = $residue
        TamperProtected     = $tamperProtected
        ThirdPartyAntivirus = $thirdParty
        IsUnprotected       = ($thirdParty.Count -eq 0)
        Blockers            = $blockers
    }
}


<#
    .SYNOPSIS
        Lists every trace of Microsoft Defender still on the machine.

    .DESCRIPTION
        Used to recognise a half-completed removal. The list covers what the removal deletes: service
        registrations, policy and configuration keys, the filter/ELAM driver files and the program data
        folders. An empty result means the machine is already clean and nothing should be attempted.

    .OUTPUTS
        System.String[]. One entry per leftover, tagged with its kind.
#>
function Get-DefenderResidue {
    $residue = @()

    foreach ($name in Get-DefenderServiceNames) {
        # The service key is the persistent state. Get-Service keeps returning a ghost entry with an
        # empty StartType after the key is gone, which would make a cleaned machine look half-removed
        # until the next reboot.
        if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name") {
            $residue += "service-key:$name"
        }
    }

    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center') {
        if (Test-Path -LiteralPath $key) { $residue += "key:$key" }
    }

    foreach ($driver in 'WdFilter.sys', 'WdNisDrv.sys', 'WdBoot.sys') {
        if (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\drivers\$driver")) {
            $residue += "driver:$driver"
        }
    }

    foreach ($folder in (Join-Path $env:ProgramFiles 'Windows Defender'),
        (Join-Path $env:ProgramFiles 'Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Support'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Security Health')) {
        if (Test-Path -LiteralPath $folder) { $residue += "folder:$folder" }
    }

    return $residue
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
    # The probes are allowed to fail - Defender cmdlets are gone once the removal ran - and the caller
    # runs with $ErrorActionPreference = 'Stop', so failures are silenced here instead of being written
    # into the transcript as terminating errors.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    try {
        try { $status = Get-MpComputerStatus } catch { $status = $null }
        if ($null -ne $status) { return [bool]$status.IsTamperProtected }

        try {
            $features = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' -Name 'TamperProtection'
        }
        catch { $features = $null }
        if ($null -ne $features) { return ([int]$features.TamperProtection -eq 5) }

        return $false
    }
    finally {
        $ErrorActionPreference = $previousPreference
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

    # TrustedInstaller owns Defender's configuration and the security service key, so an elevated
    # administrator and even a SYSTEM task get access denied. Taking ownership is what actually works
    # and it finishes in milliseconds, so it is tried before paying for a scheduled task round-trip.
    if (Remove-DefenderRegistryKeyWithOwnership -Key $Key) { return $true }

    return (Invoke-SystemRegistryDelete -Key $Key)
}


<#
    .SYNOPSIS
        Enables a privilege on the token of the current process.

    .DESCRIPTION
        SeTakeOwnershipPrivilege and SeRestorePrivilege are present in an elevated administrator token
        but disabled, which is why the registry refuses a TakeOwnership request that looks permitted.
        AdjustTokenPrivileges turns them on for this process only.

    .OUTPUTS
        System.Boolean. $true when the privilege is enabled afterwards.
#>
function Enable-TokenPrivilege {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not ('Win11DebloatTokenPrivilege' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Win11DebloatTokenPrivilege
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TokPriv1Luid
    {
        public int Count;
        public long Luid;
        public int Attr;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, int access, ref IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string system, string name, ref long luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokPriv1Luid state, int length, IntPtr previous, IntPtr returnLength);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    private const int SePrivilegeEnabled = 0x2;
    private const int TokenAdjustPrivileges = 0x20;
    private const int TokenQuery = 0x8;

    public static bool Enable(string privilege)
    {
        IntPtr token = IntPtr.Zero;
        if (!OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, ref token)) return false;

        TokPriv1Luid state = new TokPriv1Luid();
        state.Count = 1;
        state.Attr = SePrivilegeEnabled;
        if (!LookupPrivilegeValue(null, privilege, ref state.Luid)) return false;
        return AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
'@
    }

    return [Win11DebloatTokenPrivilege]::Enable($Name)
}


<#
    .SYNOPSIS
        Grants Administrators full control of a registry key and every key below it.

    .DESCRIPTION
        Ownership is the only thing standing between an elevated process and Defender's remaining keys.
        The well-known Administrators SID is used instead of a localized group name. Each key is reopened
        for enumeration because the handle used to rewrite the ACL only carries ChangePermissions.
#>
function Grant-DefenderKeyFullControl {
    param(
        [Parameter(Mandatory)]
        [string]$SubKey
    )

    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $administrators = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

    $ownerKey = $hklm.OpenSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if ($null -eq $ownerKey) { return }
    $ownerAcl = $ownerKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
    $ownerAcl.SetOwner($administrators)
    $ownerKey.SetAccessControl($ownerAcl)
    $ownerKey.Close()

    $aclKey = $hklm.OpenSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
    if ($null -eq $aclKey) { return }
    $acl = $aclKey.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $administrators,
        [System.Security.AccessControl.RegistryRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)
    $aclKey.SetAccessControl($acl)
    $aclKey.Close()

    $enumKey = $hklm.OpenSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree)
    if ($null -eq $enumKey) { return }
    $children = @($enumKey.GetSubKeyNames())
    $enumKey.Close()

    foreach ($child in $children) {
        Grant-DefenderKeyFullControl -SubKey "$SubKey\$child"
    }
}


<#
    .SYNOPSIS
        Deletes a registry key after taking ownership from TrustedInstaller.

    .OUTPUTS
        System.Boolean. $true when the key no longer exists.
#>
function Remove-DefenderRegistryKeyWithOwnership {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $Key)) { return $true }
    if ($Key -notmatch '^HKLM:') { return $false }

    $null = Enable-TokenPrivilege 'SeTakeOwnershipPrivilege'
    $null = Enable-TokenPrivilege 'SeRestorePrivilege'

    $subKey = $Key -replace '^HKLM:\\', ''
    try {
        Grant-DefenderKeyFullControl -SubKey $subKey
        Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction Stop
    }
    catch { }

    return (-not (Test-Path -LiteralPath $Key))
}


<#
    .SYNOPSIS
        Runs a command line from a one-shot task running as SYSTEM and waits for a condition to hold.

    .DESCRIPTION
        Some Defender leftovers are owned by TrustedInstaller or held open by a protected process, so an
        elevated administrator still gets access denied. Replaying the deletion with the SYSTEM token is
        the least invasive way to get the required rights without shipping a native helper. The
        temporary task and script are always cleaned up.

    .OUTPUTS
        System.Boolean. The result of the completion check.
#>
function Invoke-SystemTaskCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [scriptblock]$Completed,
        [int]$TimeoutSeconds = 15
    )

    $taskName = 'Win11DebloatDefenderCleanup'
    $stamp = [Guid]::NewGuid().ToString('N')
    $scriptPath = Join-Path $env:TEMP "Win11DebloatDefenderCleanup-$stamp.cmd"
    $logPath = Join-Path $env:TEMP "Win11DebloatDefenderCleanup-$stamp.log"

    try {
        $lines = @(
            '@echo off',
            "$Command >> `"$logPath`" 2>&1",
            'exit /b %errorlevel%'
        )
        Set-Content -LiteralPath $scriptPath -Value $lines -Encoding ASCII -Force

        & schtasks.exe /create /tn $taskName /tr "cmd.exe /c `"$scriptPath`"" /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
        & schtasks.exe /run /tn $taskName 2>&1 | Out-Null

        $deadline = $TimeoutSeconds * 2
        for ($attempt = 0; $attempt -lt $deadline; $attempt++) {
            Start-Sleep -Milliseconds 500
            if (& $Completed) { break }

            # A state that has not changed after the task ran will not change by waiting either: the
            # tools print their failure into the task log and keep quiet on success. Any output while
            # the condition still fails means the delete was refused, so stop burning the timeout.
            # Matching the text itself is not an option - the tool output is localized, and non-ASCII
            # source breaks parsing on Windows installations that do not use a UTF-8 code page.
            if ($attempt -ge 2 -and (Test-Path -LiteralPath $logPath)) {
                $taskOutput = Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($taskOutput)) {
                    break
                }
            }
        }
    }
    catch { }
    finally {
        & schtasks.exe /delete /tn $taskName /f 2>&1 | Out-Null
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    return (& $Completed)
}


<#
    .SYNOPSIS
        Deletes a registry key from a one-shot task running as SYSTEM.

    .OUTPUTS
        System.Boolean. $true when the key no longer exists.
#>
function Invoke-SystemRegistryDelete {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $quotedKey = $Key.Replace('"', '""')
    $check = { -not (Test-Path -LiteralPath $Key) }

    return (Invoke-SystemTaskCommand -Command "reg delete `"$quotedKey`" /f" -Completed $check)
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

    if (Test-Path -LiteralPath $Path) {
        # Files still mapped by a running Defender service survive the elevated delete; the SYSTEM
        # context gets past the remaining ACLs, and the caller restarts first anyway.
        $quotedPath = $Path.Replace('"', '""')
        $check = { -not (Test-Path -LiteralPath $Path) }
        $null = Invoke-SystemTaskCommand -Command "rd /s /q `"$quotedPath`"" -Completed $check -TimeoutSeconds 25
    }

    return (-not (Test-Path -LiteralPath $Path))
}


<#
    .SYNOPSIS
        Lists the services and drivers that belong to Microsoft Defender Antivirus.

    .DESCRIPTION
        Newer builds register services whose names are not in the classic list - MpDefenderCoreService
        is the obvious one, and it keeps MpClient.dll mapped, which is what makes the program folder
        undeletable. Instead of chasing names, every service whose ImagePath points into a Defender
        folder is included, on top of the known names.

    .OUTPUTS
        System.String[]
#>
function Get-DefenderServiceNames {
    $known = @(
        'WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'MpDefenderCoreService',
        'WdFilter', 'WdNisDrv', 'WdBoot', 'webthreatdefsvc', 'webthreatdefusersvc'
    )

    $discovered = @()
    try {
        foreach ($serviceKey in Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue) {
            $imagePath = (Get-ItemProperty -LiteralPath $serviceKey.PSPath -Name 'ImagePath' -ErrorAction SilentlyContinue).ImagePath
            if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
            if ($imagePath -match '(?i)windows defender|mpdefendercore|wdnis|wdfilter|wdboot') {
                $discovered += $serviceKey.PSChildName
            }
        }
    }
    catch { }

    return @(@($known) + @($discovered) | Sort-Object -Unique)
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

        # The switch is dropped so the closing summary does not warn about a reboot for work that never
        # ran. Get-RebootFeatureLabels only looks at which parameters are set, not at what succeeded.
        if ($script:Params.ContainsKey('RemoveWindowsDefender')) {
            $script:Params.Remove('RemoveWindowsDefender')
        }
        return $false
    }

    if ($preflight.ResidueOnly) {
        Write-Host (Get-ConsoleText "Defender's main service is already gone. Cleaning up {0} leftover item(s)." -FormatArgs @($preflight.Residue.Count)) -ForegroundColor Yellow
    }

    # Every service entry Defender registers, plus anything whose ImagePath points into a Defender
    # folder (MpDefenderCoreService on recent builds). WdFilter/WdNisDrv are file-system filter drivers
    # and WdBoot is the early-launch driver; deleting the service entry before the driver file is what
    # keeps Windows from booting with a start driver whose file is missing.
    $services = @(Get-DefenderServiceNames)
    $serviceKeys = @($services | ForEach-Object { "HKLM:\SYSTEM\CurrentControlSet\Services\$_" })
    # Windows Security's own antivirus registration under
    # HKLM\SOFTWARE\Microsoft\Security Center\Provider\Av is deliberately left alone: wscsvc keeps the
    # key open, so taking ownership only changes the owner and the delete still fails. It is a display
    # entry, not a component, so the registry keys above are where the removal stops.
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
        $expectedBackups = 0
        $writtenBackups = 0
        foreach ($name in $backupTargets.Keys) {
            $target = $backupTargets[$name]
            if (-not (Test-Path -LiteralPath $target)) { continue }
            $expectedBackups++
            $exportPath = Join-Path $backupRoot "$name.reg"
            & reg.exe export $target $exportPath /y 2>&1 | Out-Null
            # reg.exe can be blocked by application control policies; the file only counts if it exists
            # and actually holds a registry header, otherwise the run would report a backup that is not
            # there - which is worse than no backup at all.
            if ((Test-Path -LiteralPath $exportPath) -and ((Get-Item -LiteralPath $exportPath).Length -gt 0)) {
                $writtenBackups++
            }
        }

        if ($expectedBackups -eq 0) {
            Write-Host (Get-ConsoleText "No Defender registry keys were left to back up.")
        }
        elseif ($writtenBackups -eq $expectedBackups) {
            Write-Host (Get-ConsoleText "Backup written to {0}" -FormatArgs @($backupRoot))
        }
        else {
            Write-Warning (Get-ConsoleText "Only {0} of {1} registry keys could be exported to {2}. reg.exe may be blocked by an application control policy." -FormatArgs @($writtenBackups, $expectedBackups, $backupRoot))
        }
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

        if (Test-Path -LiteralPath $driverFile) {
            # A driver still mapped by the kernel cannot be deleted by any token. Retry from SYSTEM in
            # case it is only an ACL problem, otherwise it is reported as a leftover for the next boot.
            $quotedDriver = $driverFile.Replace('"', '""')
            $check = { -not (Test-Path -LiteralPath $driverFile) }
            $null = Invoke-SystemTaskCommand -Command "del /f /q `"$quotedDriver`"" -Completed $check -TimeoutSeconds 15
        }
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
    # Judged on the service key, not on Get-Service: the service manager keeps a ghost entry whose
    # StartType is empty after the key is deleted, and that must not read as "still installed".
    $serviceGone = -not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend')

    if ($serviceGone) {
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

    # TrustedInstaller-owned keys and files mapped by a running driver survive even a SYSTEM retry, so
    # report what is actually left instead of letting the green success line imply a clean machine.
    $remaining = @(Get-DefenderResidue)
    if ($remaining.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These leftovers survived the cleanup and will need a reboot or manual removal: {0}" -FormatArgs @(($remaining -join ', ')))
    }
    else {
        Write-Host (Get-ConsoleText "No Defender leftovers detected.") -ForegroundColor Green
    }

    return $serviceGone
}
