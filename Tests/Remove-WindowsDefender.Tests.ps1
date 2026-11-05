BeforeAll {
    # Console text is normally provided by Import-LanguageFile; these tests only assert behaviour, so a
    # passthrough that still applies -FormatArgs is enough and keeps the assertions readable.
    function Get-ConsoleText {
        param(
            [Parameter(Position = 0)][string]$Text,
            [object[]]$FormatArgs = $null
        )
        if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
            try { return ($Text -f $FormatArgs) } catch { return $Text }
        }
        return $Text
    }

    . (Join-Path $PSScriptRoot '..\Scripts\Features\Remove-WindowsDefender.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\GUI\Confirm-DefenderRemoval.ps1')

    $script:Params = @{}
    $script:GuiWindow = $null
    $script:DefenderRemovalConfirmed = $false
    $script:RegistryBackupsPath = Join-Path $TestDrive 'Backups'
}

Describe 'Get-DefenderThirdPartyAntivirus' {
    It 'returns third-party products and ignores Defender' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ displayName = 'Windows Defender' },
                [pscustomobject]@{ displayName = 'Microsoft Defender Antivirus' },
                [pscustomobject]@{ displayName = 'Kaspersky Standard' }
            )
        } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }

        $result = @(Get-DefenderThirdPartyAntivirus)

        $result | Should -Be @('Kaspersky Standard')
    }

    It 'returns nothing when SecurityCenter2 cannot be queried' {
        Mock Get-CimInstance { throw 'not available' } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }

        $result = @(Get-DefenderThirdPartyAntivirus)

        $result | Should -HaveCount 0
    }
}

Describe 'Test-DefenderTamperProtection' {
    It 'reports tamper protection from Get-MpComputerStatus' {
        Mock Get-MpComputerStatus { [pscustomobject]@{ IsTamperProtected = $true } }

        Test-DefenderTamperProtection | Should -BeTrue
    }

    It 'falls back to the registry value when Defender cmdlets are unavailable' {
        Mock Get-MpComputerStatus { throw 'cmdlet missing' }
        Mock Get-ItemProperty {
            [pscustomobject]@{ TamperProtection = 5 }
        } -ParameterFilter { $Path -like '*Windows Defender\Features*' }

        Test-DefenderTamperProtection | Should -BeTrue
    }

    It 'treats an unreadable state as unprotected so the removal is not blocked forever' {
        Mock Get-MpComputerStatus { throw 'cmdlet missing' }
        Mock Get-ItemProperty { throw 'key missing' } -ParameterFilter { $Path -like '*Windows Defender\Features*' }

        Test-DefenderTamperProtection | Should -BeFalse
    }
}

Describe 'Invoke-RemoveWindowsDefender' {
    BeforeEach {
        $script:Params = @{ WhatIf = $true }
    }

    It 'only prints the plan in WhatIf and reports success' {
        Mock Test-DefenderRemovalIsAdmin { $true }
        Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend' } } -ParameterFilter { $Name -eq 'WinDefend' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*WinDefend*' }
        Mock Get-MpComputerStatus { [pscustomobject]@{ IsTamperProtected = $false } }
        Mock Get-CimInstance { @([pscustomobject]@{ displayName = 'Kaspersky Standard' }) } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }
        Mock Remove-Item { throw 'WhatIf must not delete anything' }

        $output = Invoke-RemoveWindowsDefender 6>&1 | Out-String

        $output | Should -Match '\[WhatIf\]'
        Should -Invoke Remove-Item -Times 0
    }

    It 'refuses to run when tamper protection is on' {
        $script:Params = @{}
        Mock Test-DefenderRemovalIsAdmin { $true }
        Mock Get-Service { [pscustomobject]@{ Name = 'WinDefend' } } -ParameterFilter { $Name -eq 'WinDefend' }
        Mock Get-MpComputerStatus { [pscustomobject]@{ IsTamperProtected = $true } }
        Mock Get-CimInstance { @() } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }
        Mock Remove-Item { throw 'must not delete anything when blocked' }

        $result = Invoke-RemoveWindowsDefender 3>$null

        $result | Should -BeFalse
        Should -Invoke Remove-Item -Times 0
    }
}

Describe 'Get-DefenderResidue' {
    BeforeEach {
        # The runtime-class and Ubpm lookups enumerate the live registry; keep the tests hermetic.
        Mock Get-ChildItem { @() }
    }

    It 'reports a leftover service key even when the service is no longer running' {
        Mock Get-DefenderServiceNames { @('WinDefend', 'WdFilter') }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Services\WdFilter' }
        Mock Test-Path { $false }

        $residue = @(Get-DefenderResidue)

        $residue | Should -Contain 'service-key:WdFilter'
        $residue | Should -Not -Contain 'service-key:WinDefend'
    }

    It 'returns nothing on a fully cleaned machine' {
        Mock Get-DefenderServiceNames { @('WinDefend') }
        Mock Test-Path { $false }

        $residue = @(Get-DefenderResidue)

        $residue | Should -HaveCount 0
    }
}

Describe 'Get-DefenderRemovalPreflight' {
    BeforeEach {
        Mock Get-ChildItem { @() }
    }

    It 'recognises a half-finished removal instead of refusing to clean it up' {
        Mock Test-DefenderRemovalIsAdmin { $true }
        Mock Get-Service { $null } -ParameterFilter { $Name -eq 'WinDefend' }
        Mock Get-DefenderServiceNames { @('WinDefend', 'WdFilter') }
        Mock Test-Path { $false }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Services\WdFilter' }
        Mock Get-MpComputerStatus { [pscustomobject]@{ IsTamperProtected = $false } }
        Mock Get-CimInstance { @([pscustomobject]@{ displayName = 'Kaspersky Standard' }) } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }

        $result = Get-DefenderRemovalPreflight

        $result.DefenderPresent | Should -BeTrue
        $result.Installed | Should -BeFalse
        $result.ResidueOnly | Should -BeTrue
        $result.Blockers | Should -HaveCount 0
    }

    It 'blocks when nothing of Defender is left on the machine' {
        Mock Test-DefenderRemovalIsAdmin { $true }
        Mock Get-Service { $null } -ParameterFilter { $Name -eq 'WinDefend' }
        Mock Get-DefenderServiceNames { @('WinDefend') }
        Mock Test-Path { $false }
        Mock Get-MpComputerStatus { [pscustomobject]@{ IsTamperProtected = $false } }
        Mock Get-CimInstance { @() } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' }

        $result = Get-DefenderRemovalPreflight

        $result.DefenderPresent | Should -BeFalse
        $result.Blockers | Should -Contain 'Microsoft Defender Antivirus is not present'
    }
}

Describe 'Remove-DefenderRegistryKeyWithOwnership' {
    It 'leaves keys outside HKLM to the caller' {
        # Taking ownership only makes sense for machine keys; the guard must not touch the hive.
        Remove-DefenderRegistryKeyWithOwnership -Key 'HKCU:\Software' | Should -BeFalse
    }
}

Describe 'Enable-TokenPrivilege' {
    It 'rejects an unknown privilege name without throwing' {
        Enable-TokenPrivilege 'SeNoSuchPrivilegeExists' | Should -BeFalse
        ('Win11DebloatTokenPrivilege' -as [type]) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-DefenderServiceNames' {
    It 'includes the MsSec platform drivers that the ImagePath scan cannot recognise' {
        Mock Get-ChildItem { @() }

        $names = @(Get-DefenderServiceNames)

        $names | Should -Contain 'MsSecCore'
        $names | Should -Contain 'MsSecFlt'
        $names | Should -Contain 'MsSecWfp'
    }
}

Describe 'Get-DefenderRegistryKeyTargets' {
    It 'covers shell, event tracing, Windows Security and web threat defence registration' {
        $keys = @(Get-DefenderRegistryKeyTargets)

        $keys | Should -Contain 'HKLM:\SOFTWARE\Microsoft\Windows Security Health'
        $keys | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderAuditLogger'
        $keys | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderApiLogger'
        $keys | Should -Contain 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost\WebThreatDefense'
        $keys | Should -Contain 'HKLM:\SOFTWARE\Microsoft\WindowsRuntime\Server\WebThreatDefSvc'
        $keys | Should -Contain 'HKLM:\SOFTWARE\Classes\AppUserModelId\Windows.Defender'
        $keys | Should -Contain 'HKLM:\SOFTWARE\Classes\WindowsDefender'
    }
}

Describe 'Get-DefenderClsidTargets' {
    It 'returns both the 64-bit and the WOW6432Node registration of every class' {
        $targets = @(Get-DefenderClsidTargets)

        $targets | Should -HaveCount 26
        $targets | Should -Contain 'HKLM:\SOFTWARE\Classes\CLSID\{2781761E-28E0-4109-99FE-B9D127C57AFE}'
        $targets | Should -Contain 'HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\{2781761E-28E0-4109-99FE-B9D127C57AFE}'
    }
}

Describe 'Get-DefenderFirewallRuleNames' {
    It 'recognises rule names and rule blobs that name Defender' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                PSPath                     = 'Microsoft.PowerShell.Core\Registry::test'
                PSParentPath               = 'Microsoft.PowerShell.Core\Registry::test-parent'
                PSChildName                = 'System'
                PSDrive                    = 'HKLM'
                PSProvider                 = 'Microsoft.PowerShell.Core\Registry'
                'WindowsDefender-1'        = 1
                'WebThreatDefSvc_Allow_In' = 1
                '{2A5FE97D-01A4-4A9C-8241-BB3755B65EE0}' = [System.Text.Encoding]::Unicode.GetBytes('C:\Program Files\Windows Defender\MsMpEng.exe')
                'UnrelatedRule'            = [System.Text.Encoding]::Unicode.GetBytes('C:\Windows\explorer.exe')
            }
        }

        $names = @(Get-DefenderFirewallRuleNames -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Static\System')

        $names | Should -Contain 'WindowsDefender-1'
        $names | Should -Contain 'WebThreatDefSvc_Allow_In'
        $names | Should -Contain '{2A5FE97D-01A4-4A9C-8241-BB3755B65EE0}'
        $names | Should -Not -Contain 'UnrelatedRule'
    }
}

Describe 'Remove-DefenderRegistryValue' {
    It 'treats a missing key as already removed' {
        Mock Test-Path { $false }

        Remove-DefenderRegistryValue -Key 'HKLM:\SOFTWARE\NoSuchKey' -Name 'WindowsDefender' | Should -BeTrue
    }
}

Describe 'Get-DefenderRemovalReport' {
    It 'fails a leftover service key and only warns about a leftover driver file' {
        Mock Get-DefenderServiceNames { @('WinDefend') }
        Mock Get-DefenderRegistryKeyTargets { @() }
        Mock Get-DefenderRuntimeClassKeys { @() }
        Mock Get-DefenderUbpmTargets { @() }
        Mock Get-DefenderRegistryValueTargets { @() }
        Mock Get-DefenderClsidTargets { @() }
        Mock Get-DefenderDriverFiles { @('C:\Windows\System32\drivers\WdFilter.sys') }
        Mock Get-DefenderFolderTargets { @() }
        Mock Get-DefenderScheduledTaskNames { @() }
        Mock Get-DefenderFirewallRuleNames { @() }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Services\WinDefend' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*WdFilter.sys' }
        Mock Test-Path { $false }
        Mock Get-Process { $null }

        $rows = @(Get-DefenderRemovalReport)

        ($rows | Where-Object { $_.Item -eq 'WinDefend' }).Status | Should -Be 'Fail'
        ($rows | Where-Object { $_.Item -eq 'WdFilter.sys' }).Status | Should -Be 'Warn'
    }

    It 'reports nothing but OK rows on a cleaned machine' {
        Mock Get-DefenderServiceNames { @('WinDefend', 'WdFilter') }
        Mock Get-DefenderRegistryKeyTargets { @('HKLM:\SOFTWARE\Microsoft\Windows Defender') }
        Mock Get-DefenderRuntimeClassKeys { @() }
        Mock Get-DefenderUbpmTargets { @() }
        Mock Get-DefenderRegistryValueTargets { @() }
        Mock Get-DefenderClsidTargets { @() }
        Mock Get-DefenderDriverFiles { @('C:\Windows\System32\drivers\WdFilter.sys') }
        Mock Get-DefenderFolderTargets { @() }
        Mock Get-DefenderScheduledTaskNames { @() }
        Mock Get-DefenderFirewallRuleNames { @() }
        Mock Test-Path { $false }
        Mock Get-Process { $null }
        Mock Get-Service { $null }

        $rows = @(Get-DefenderRemovalReport)

        @($rows | Where-Object { $_.Status -ne 'Ok' }) | Should -HaveCount 0
    }
}

Describe 'Confirm-DefenderRemovalIfSelected' {
    BeforeEach {
        $script:DefenderRemovalConfirmed = $false
        $script:GuiWindow = $null
    }

    It 'does nothing when the feature is not selected' {
        $script:Params = @{}

        Confirm-DefenderRemovalIfSelected | Should -BeTrue
    }

    It 'honours the explicit opt-in used by unattended runs' {
        $script:Params = @{ RemoveWindowsDefender = $true; AcceptDefenderRemovalRisk = $true }

        Confirm-DefenderRemovalIfSelected | Should -BeTrue
        $script:DefenderRemovalConfirmed | Should -BeTrue
    }

    It 'drops the feature in Silent mode without the opt-in instead of prompting' {
        $script:Params = @{ RemoveWindowsDefender = $true; Silent = $true }

        Confirm-DefenderRemovalIfSelected 3>$null | Should -BeFalse
        $script:Params.ContainsKey('RemoveWindowsDefender') | Should -BeFalse
    }

    It 'does not prompt again once the removal is already confirmed' {
        $script:Params = @{ RemoveWindowsDefender = $true; Silent = $true }
        $script:DefenderRemovalConfirmed = $true

        Confirm-DefenderRemovalIfSelected | Should -BeTrue
        $script:Params.ContainsKey('RemoveWindowsDefender') | Should -BeTrue
    }
}
