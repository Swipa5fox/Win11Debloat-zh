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

    foreach ($key in @(Get-DefenderRegistryKeyTargets) + @(Get-DefenderClsidTargets) + @(Get-DefenderRuntimeClassKeys) + @(Get-DefenderUbpmTargets)) {
        if (Test-Path -LiteralPath $key) { $residue += "key:$key" }
    }

    foreach ($driver in Get-DefenderDriverFiles) {
        if (Test-Path -LiteralPath $driver) { $residue += "driver:$driver" }
    }

    foreach ($folder in Get-DefenderFolderTargets) {
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
        'WdFilter', 'WdNisDrv', 'WdBoot', 'webthreatdefsvc', 'webthreatdefusersvc',
        # Defender platform drivers that recent builds register next to the antivirus. Their
        # ImagePath points at System32\drivers rather than a Defender folder, so the path scan
        # below cannot recognise them, and leaving them behind keeps the platform half-installed.
        'MsSecCore', 'MsSecFlt', 'MsSecWfp'
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
        Lists the registry keys that exist only because Microsoft Defender is installed.

    .DESCRIPTION
        Deleting the services alone leaves the shell, COM and WinRT registration behind, which is what
        makes a "removed" Defender still show up in Windows Security and in the context menu. The list
        is shared by the removal, the residue check and the verification report so all three agree on
        what counts as removed.

        Keys are deleted whole; single values (Run entries, the Svchost host group) are handled by
        Get-DefenderRegistryValueTargets, and the per-class COM registration by Get-DefenderClsidTargets.

    .OUTPUTS
        System.String[]
#>
function Get-DefenderRegistryKeyTargets {
    return @(
        # Configuration and policy
        'HKLM:\SOFTWARE\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center',
        # Windows Security: the app's registration, its COM class and its Control Panel entry
        'HKLM:\SOFTWARE\Microsoft\Windows Security Health',
        'HKLM:\SOFTWARE\Classes\CLSID\{BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6}',
        'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6}',
        # Web threat defence: the service is gone, its host group and WinRT server are not
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost\WebThreatDefense',
        'HKLM:\SOFTWARE\Microsoft\WindowsRuntime\Server\WebThreatDefSvc',
        # Event tracing sessions Defender registers at install time
        'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderAuditLogger',
        'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderApiLogger',
        # Shell registration: AppUserModelId, the WindowsDefender progid and the AppX class
        'HKLM:\SOFTWARE\Classes\AppUserModelId\Windows.Defender',
        'HKLM:\SOFTWARE\Classes\AppUserModelId\Microsoft.Windows.Defender',
        'HKLM:\SOFTWARE\Classes\WindowsDefender',
        'HKLM:\SOFTWARE\Classes\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0'
    )
}


<#
    .SYNOPSIS
        Lists the COM classes Defender registers.

    .DESCRIPTION
        These classes back the shell integration and the Windows Security UI. A GUID that is not
        present is skipped by the caller, and HKCR is only a merged view over HKLM\SOFTWARE\Classes,
        so deleting there would be the same operation twice.

    .OUTPUTS
        System.String[]. Registry paths, not bare GUIDs.
#>
function Get-DefenderClsidTargets {
    $guids = @(
        '{2781761E-28E0-4109-99FE-B9D127C57AFE}',
        '{2781761E-28E2-4109-99FE-B9D127C57AFE}',
        '{195B4D07-3DE2-4744-BBF2-D90121AE785B}',
        '{361290c0-cb1b-49ae-9f3e-ba1cbe5dab35}',
        '{45F2C32F-ED16-4C94-8493-D72EF93A051B}',
        '{6CED0DAA-4CDE-49C9-BA3A-AE163DC3D7AF}',
        '{8a696d12-576b-422e-9712-01b9dd84b446}',
        '{8C9C0DB7-2CBA-40F1-AFE0-C55740DD91A0}',
        '{A2D75874-6750-4931-94C1-C99D3BC9D0C7}',
        '{A7C452EF-8E9F-42EB-9F2B-245613CA0DC9}',
        '{DACA056E-216A-4FD1-84A6-C306A017ECEC}',
        '{E3C9166D-1D39-4D4E-A45D-BC7BE9B00578}',
        '{F6976CF5-68A8-436C-975A-40BE53616D59}'
    )

    $targets = @()
    foreach ($guid in $guids) {
        foreach ($root in 'HKLM:\SOFTWARE\Classes\CLSID', 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID') {
            $targets += "$root\$guid"
        }
    }
    return $targets
}


<#
    .SYNOPSIS
        Lists the WinRT classes that belong to web threat defence.

    .DESCRIPTION
        The classes are named per component and change between builds, so they are discovered by
        name instead of being hardcoded.

    .OUTPUTS
        System.String[]. Registry paths.
#>
function Get-DefenderRuntimeClassKeys {
    $root = 'HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId'
    $keys = @()
    try {
        foreach ($child in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            if ($child.PSChildName -match '(?i)webthreatdefense') {
                $keys += "$root\$($child.PSChildName)"
            }
        }
    }
    catch { }

    return $keys
}


<#
    .SYNOPSIS
        Lists the Ubpm maintenance entries Defender registers.

    .OUTPUTS
        System.String[]. Registry paths.
#>
function Get-DefenderUbpmTargets {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Ubpm'
    $keys = @()
    try {
        foreach ($child in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            if ($child.PSChildName -match '(?i)defender') {
                $keys += "$root\$($child.PSChildName)"
            }
        }
    }
    catch { }

    return $keys
}


<#
    .SYNOPSIS
        Lists the individual registry values Defender writes outside its own keys.

    .DESCRIPTION
        Autostart entries and the Svchost host group are values inside keys that belong to Windows
        itself, so they are deleted by name rather than by deleting the key. Only the current user's
        HKCU is handled: loading another user's hive to look for a stale Defender autostart entry is
        more invasive than the entry is worth.

    .OUTPUTS
        PSCustomObject[]. One entry per key, with the value names to delete.
#>
function Get-DefenderRegistryValueTargets {
    $autostartNames = @('WindowsDefender', 'Windows Defender', 'SecurityHealth')

    return @(
        [PSCustomObject]@{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Names = $autostartNames },
        [PSCustomObject]@{ Key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Names = $autostartNames },
        [PSCustomObject]@{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Names = $autostartNames },
        [PSCustomObject]@{ Key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Names = $autostartNames },
        # The Svchost value names the service group; the group key is deleted with the other keys.
        [PSCustomObject]@{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost'; Names = @('WebThreatDefense') }
    )
}


<#
    .SYNOPSIS
        Tests whether a registry value exists.

    .OUTPUTS
        System.Boolean
#>
function Test-DefenderRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Key)) { return $false }
    try {
        $null = Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}


<#
    .SYNOPSIS
        Deletes a single registry value and reports whether it is gone.

    .OUTPUTS
        System.Boolean. $true when the value or the whole key is absent afterwards.
#>
function Remove-DefenderRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Key)) { return $true }
    if (-not (Test-DefenderRegistryValue -Key $Key -Name $Name)) { return $true }

    try {
        Remove-ItemProperty -LiteralPath $Key -Name $Name -Force -ErrorAction Stop
    }
    catch { }

    return (-not (Test-DefenderRegistryValue -Key $Key -Name $Name))
}


<#
    .SYNOPSIS
        Lists the firewall rule values that belong to Defender or web threat defence.

    .DESCRIPTION
        Firewall rules are stored as values, not as keys: the value name is either the rule name
        (WindowsDefender-1, WebThreatDefSvc_Allow_In, ...) or a GUID whose data is a rule blob. The
        blob is UTF-16 text holding the program path, so the Defender entries are recognised by
        content rather than by a hardcoded GUID list that changes between builds.

    .OUTPUTS
        System.String[]. Value names inside the given key.
#>
function Get-DefenderFirewallRuleNames {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $names = @()
    if (-not (Test-Path -LiteralPath $Key)) { return $names }

    try {
        $properties = Get-ItemProperty -LiteralPath $Key -ErrorAction Stop
    }
    catch {
        return $names
    }

    foreach ($property in $properties.PSObject.Properties) {
        # Get-ItemProperty adds PSPath/PSParentPath/PSChildName/PSDrive/PSProvider to the output.
        if ($property.Name -like 'PS*') { continue }

        if ($property.Name -match '(?i)^WindowsDefender(-?\d+)?$' -or $property.Name -match '(?i)^WebThreatDefSvc') {
            $names += $property.Name
            continue
        }

        if ($property.Value -is [byte[]]) {
            $blob = ''
            try { $blob = [System.Text.Encoding]::Unicode.GetString($property.Value) } catch { }
            if ($blob -match '(?i)windows defender|webthreatdef') { $names += $property.Name }
        }
    }

    return $names
}


<#
    .SYNOPSIS
        Deletes the firewall rule values that belong to Defender.

    .OUTPUTS
        PSCustomObject with Removed (count) and Failed (value names).
#>
function Remove-DefenderFirewallRules {
    $keys = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Static\System',
        'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Configurable\System'
    )

    $removed = 0
    $failed = @()

    foreach ($key in $keys) {
        $names = @(Get-DefenderFirewallRuleNames -Key $key)
        if ($names.Count -eq 0) { continue }

        # These keys are owned by TrustedInstaller and grant Administrators read access only, so the
        # delete is attempted first and the key is taken over only when it is actually refused.
        # Deleting the whole key is not an option: it also holds rules owned by other components.
        $ownershipTaken = $false

        foreach ($name in $names) {
            try {
                Remove-ItemProperty -LiteralPath $key -Name $name -Force -ErrorAction Stop
                $removed++
                continue
            }
            catch { }

            if (-not $ownershipTaken) {
                $null = Enable-TokenPrivilege 'SeTakeOwnershipPrivilege'
                $null = Enable-TokenPrivilege 'SeRestorePrivilege'
                try { Grant-DefenderKeyFullControl -SubKey ($key -replace '^HKLM:\\', '') } catch { }
                $ownershipTaken = $true
            }

            try {
                Remove-ItemProperty -LiteralPath $key -Name $name -Force -ErrorAction Stop
                $removed++
            }
            catch {
                $failed += $name
            }
        }
    }

    return [PSCustomObject]@{
        Removed = $removed
        Failed  = $failed
    }
}


<#
    .SYNOPSIS
        Lists the scheduled tasks Defender registers.

    .OUTPUTS
        System.String[]. Task names, or an empty array when the task service cannot be queried.
#>
function Get-DefenderScheduledTaskNames {
    $names = @()
    foreach ($path in '\Microsoft\Windows\Windows Defender\*', '\Microsoft\Windows\Defender\*') {
        try {
            foreach ($task in @(Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue)) {
                if ($task) { $names += [string]$task.TaskName }
            }
        }
        catch { }
    }

    return $names
}


<#
    .SYNOPSIS
        Lists the filter, ELAM and platform driver files Defender installs.

    .OUTPUTS
        System.String[]. Absolute paths.
#>
function Get-DefenderDriverFiles {
    return @(
        'WdFilter.sys', 'WdNisDrv.sys', 'WdBoot.sys',
        # Platform drivers registered by the MsSec* services
        'msseccore.sys', 'mssecflt.sys', 'mssecwfp.sys'
    ) | ForEach-Object { Join-Path $env:SystemRoot "System32\drivers\$_" }
}


<#
    .SYNOPSIS
        Lists the program and data folders Defender owns.

    .OUTPUTS
        System.String[]. Absolute paths.
#>
function Get-DefenderFolderTargets {
    return @(
        (Join-Path $env:ProgramFiles 'Windows Defender'),
        (Join-Path $env:ProgramFiles 'Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Advanced Threat Protection'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender Support'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Security Health')
    )
}


<#
    .SYNOPSIS
        Reports what is still on the machine after a Defender removal, grouped and judged.

    .DESCRIPTION
        A read-only counterpart to Invoke-RemoveWindowsDefender, meant to be run after a restart.
        Status is Fail when a component that should be deleted is still registered, Warn when a
        leftover needs a reboot or a manual delete, and Ok otherwise.

    .OUTPUTS
        PSCustomObject[]. One row per checked item with Group, Item and Status.
#>
function Get-DefenderRemovalReport {
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($name in Get-DefenderServiceNames) {
        $status = if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name") { 'Fail' } else { 'Ok' }
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckServices'; Item = $name; Status = $status })
    }

    foreach ($key in @(Get-DefenderRegistryKeyTargets) + @(Get-DefenderRuntimeClassKeys) + @(Get-DefenderUbpmTargets)) {
        $status = if (Test-Path -LiteralPath $key) { 'Fail' } else { 'Ok' }
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckRegistry'; Item = $key; Status = $status })
    }

    foreach ($target in Get-DefenderRegistryValueTargets) {
        foreach ($name in $target.Names) {
            $status = if (Test-DefenderRegistryValue -Key $target.Key -Name $name) { 'Warn' } else { 'Ok' }
            $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckStartup'; Item = "$($target.Key)\$name"; Status = $status })
        }
    }

    # A COM class left behind is not a running component, so it is a leftover rather than a failure.
    foreach ($key in Get-DefenderClsidTargets) {
        $status = if (Test-Path -LiteralPath $key) { 'Warn' } else { 'Ok' }
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckCom'; Item = $key; Status = $status })
    }

    foreach ($driver in Get-DefenderDriverFiles) {
        $status = if (Test-Path -LiteralPath $driver) { 'Warn' } else { 'Ok' }
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckDrivers'; Item = (Split-Path -Leaf $driver); Status = $status })
    }

    foreach ($folder in Get-DefenderFolderTargets) {
        $status = if (Test-Path -LiteralPath $folder) { 'Warn' } else { 'Ok' }
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckFolders'; Item = $folder; Status = $status })
    }

    foreach ($task in Get-DefenderScheduledTaskNames) {
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckTasks'; Item = $task; Status = 'Warn' })
    }

    foreach ($key in @(
            'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Static\System',
            'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Configurable\System'
        )) {
        foreach ($name in Get-DefenderFirewallRuleNames -Key $key) {
            $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckFirewall'; Item = $name; Status = 'Warn' })
        }
    }

    # Consistency: state that contradicts itself, rather than an item that simply survived.
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend')) {
        $ghost = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
        if ($null -ne $ghost) {
            $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckConsistency'; Item = 'WinDefend is still listed by the service control manager'; Status = 'Warn' })
        }
    }

    if ($null -ne (Get-Process -Name 'MsMpEng' -ErrorAction SilentlyContinue)) {
        $rows.Add([PSCustomObject]@{ Group = 'DefenderCheckConsistency'; Item = 'MsMpEng is still running'; Status = 'Fail' })
    }

    return @($rows.ToArray())
}


<#
    .SYNOPSIS
        Prints the Defender removal report to the console.

    .OUTPUTS
        System.Boolean. $true when no item is reported as failed.
#>
function Show-DefenderRemovalReport {
    $rows = @(Get-DefenderRemovalReport)

    Write-Host ""
    Write-Host (Get-ConsoleText "Microsoft Defender removal check") -ForegroundColor Cyan

    foreach ($group in @($rows | Group-Object -Property Group)) {
        $failed = @($group.Group | Where-Object { $_.Status -eq 'Fail' }).Count
        $warned = @($group.Group | Where-Object { $_.Status -eq 'Warn' }).Count
        $passed = @($group.Group | Where-Object { $_.Status -eq 'Ok' }).Count

        $color = if ($failed -gt 0) { 'Red' } elseif ($warned -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host (Get-ConsoleText "{0}: {1} ok, {2} warning(s), {3} failed" -FormatArgs @((Get-ConsoleText $group.Name), $passed, $warned, $failed)) -ForegroundColor $color

        foreach ($row in @($group.Group | Where-Object { $_.Status -ne 'Ok' })) {
            $label = if ($row.Status -eq 'Fail') { Get-ConsoleText "DefenderCheckFail" } else { Get-ConsoleText "DefenderCheckWarn" }
            Write-Host ("    [{0}] {1}" -f $label, $row.Item) -ForegroundColor $color
        }
    }

    $failCount = @($rows | Where-Object { $_.Status -eq 'Fail' }).Count
    $warnCount = @($rows | Where-Object { $_.Status -eq 'Warn' }).Count

    Write-Host ""
    if ($failCount -eq 0 -and $warnCount -eq 0) {
        Write-Host (Get-ConsoleText "All checks passed: no trace of Microsoft Defender is left.") -ForegroundColor Green
    }
    else {
        Write-Host (Get-ConsoleText "{0} blocking item(s) and {1} leftover item(s) remain." -FormatArgs @($failCount, $warnCount)) -ForegroundColor Yellow
    }

    return ($failCount -eq 0)
}


<#
    .SYNOPSIS
        Permanently removes Microsoft Defender Antivirus from the machine.

    .DESCRIPTION
        Unsupported by Microsoft. On Windows client there is no optional feature to uninstall, so this
        deletes the service registrations (WinDefend, WdNisSvc, Sense, SecurityHealthService, the MsSec*
        platform drivers), the filter and ELAM drivers (WdFilter, WdNisDrv, WdBoot), Defender's policy
        and configuration keys, its shell, COM and WinRT registration, the WebThreatDefense host group,
        its autostart entries and firewall rules, its scheduled tasks, and the program/data folders.
        The removal cannot be undone from this tool: recovery requires an in-place upgrade or a clean
        install, and a Windows feature upgrade brings Defender back.

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
    $configKeys = @(Get-DefenderRegistryKeyTargets)
    $clsidKeys = @(Get-DefenderClsidTargets)
    # WinRT classes and Ubpm maintenance entries are discovered by name, so both lists are dynamic.
    $runtimeKeys = @(Get-DefenderRuntimeClassKeys) + @(Get-DefenderUbpmTargets)
    $valueTargets = @(Get-DefenderRegistryValueTargets)
    $driverFiles = @(Get-DefenderDriverFiles)
    $folders = @(Get-DefenderFolderTargets)

    if ($whatIf) {
        Write-Host (Get-ConsoleText "[WhatIf] Remove Microsoft Defender Antivirus") -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Stop and delete services: {0}" -FormatArgs @(($services -join ', '))) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete registry keys: {0}" -FormatArgs @((($serviceKeys + $configKeys) -join ', '))) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete COM registrations and WebThreatDefense leftovers: {0}" -FormatArgs @(($clsidKeys + $runtimeKeys).Count)) -ForegroundColor Cyan
        Write-Host (Get-ConsoleText "[WhatIf] Delete autostart entries and firewall rules that belong to Defender") -ForegroundColor Cyan
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

    # ---- Phase 5: configuration, shell, COM and WinRT registration ----
    Write-Host (Get-ConsoleText "> Deleting Defender registry keys...")
    $failedKeys = @()
    foreach ($configKey in @($configKeys) + @($clsidKeys) + @($runtimeKeys)) {
        if (-not (Remove-DefenderRegistryKey -Key $configKey)) {
            $failedKeys += $configKey
        }
    }

    # ---- Phase 5b: autostart entries and the Svchost host group ----
    # These live in keys that belong to Windows, so they are deleted value by value.
    Write-Host (Get-ConsoleText "> Removing Defender autostart entries...")
    $failedValues = @()
    foreach ($target in $valueTargets) {
        foreach ($valueName in $target.Names) {
            if (-not (Remove-DefenderRegistryValue -Key $target.Key -Name $valueName)) {
                $failedValues += "$($target.Key)\$valueName"
            }
        }
    }

    # ---- Phase 5c: firewall rules ----
    Write-Host (Get-ConsoleText "> Removing Defender firewall rules...")
    $firewallResult = Remove-DefenderFirewallRules
    if ($firewallResult.Removed -gt 0) {
        Write-Host (Get-ConsoleText "Removed {0} Defender firewall rule(s)." -FormatArgs @($firewallResult.Removed))
    }
    if ($firewallResult.Failed.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These firewall rules could not be removed: {0}" -FormatArgs @(($firewallResult.Failed -join ', ')))
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
    if ($failedValues.Count -gt 0) {
        Write-Warning (Get-ConsoleText "These registry values could not be deleted: {0}" -FormatArgs @(($failedValues -join ', ')))
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
