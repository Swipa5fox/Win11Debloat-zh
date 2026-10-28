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
