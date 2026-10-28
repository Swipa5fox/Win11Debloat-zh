<#
    .SYNOPSIS
        Confirms that the user really wants Microsoft Defender Antivirus removed.

    .DESCRIPTION
        Removal cannot be undone from this tool, so a single Yes/No click is not enough. The GUI path
        shows a dedicated dialog listing the consequences and only accepts the typed word REMOVE; the
        console path does the same through Read-Host. Unattended runs have to opt in explicitly with
        -AcceptDefenderRemovalRisk, otherwise the feature is skipped instead of silently applied.

        Preconditions are checked first: tamper protection, a missing Defender, or a missing third-party
        antivirus are reported before the user is asked to type anything, so nobody confirms a removal
        that would fail halfway.

    .OUTPUTS
        System.Boolean. $true when the removal may proceed.
#>
function Confirm-DefenderRemoval {
    param(
        [System.Windows.Window]$Owner = $null
    )

    $preflight = Get-DefenderRemovalPreflight

    # Hard blockers: Defender is protected, absent, or we are not elevated.
    if ($preflight.Blockers.Count -gt 0) {
        foreach ($blocker in $preflight.Blockers) {
            Write-Warning (Get-ConsoleText "Cannot remove Microsoft Defender Antivirus: {0}" -FormatArgs @($blocker))
        }
        if ($preflight.TamperProtected -and $script:GuiWindow) {
            Show-MessageBox -Message (Get-ConsoleText "Tamper protection is on. Turn it off in Windows Security under Virus & threat protection > Manage settings, then run this again.") `
                -Title (Get-Translation -Key 'DefenderRemovalConfirmTitle') -Button 'OK' -Icon 'Warning' -Owner $Owner | Out-Null
        }
        return $false
    }

    $unprotectedWarning = ''
    if ($preflight.IsUnprotected) {
        $unprotectedWarning = Get-ConsoleText "No third-party antivirus is registered. After this runs, nothing on this machine will scan files, and Windows Security will report that no antivirus is active."
        Write-Warning $unprotectedWarning
    }
    else {
        Write-Host (Get-ConsoleText "Third-party antivirus detected, it keeps protecting this machine after Defender is gone: {0}" -FormatArgs @(($preflight.ThirdPartyAntivirus -join ', ')))
    }

    # ---- Console path ----
    if (-not $script:GuiWindow -or -not (Test-Path -LiteralPath $script:DefenderRemovalConfirmSchema)) {
        Write-Host ""
        Write-Host (Get-ConsoleText "Microsoft Defender Antivirus will be permanently removed:") -ForegroundColor Red
        Write-Host (Get-ConsoleText "  - services, filter/ELAM drivers, policies, scheduled tasks and program folders are deleted") -ForegroundColor Red
        Write-Host (Get-ConsoleText "  - this cannot be undone from this tool; recovery needs an in-place upgrade or a clean install") -ForegroundColor Red
        Write-Host (Get-ConsoleText "  - a Windows feature upgrade will bring Defender back and the removal has to be repeated") -ForegroundColor Red
        if ($unprotectedWarning) {
            Write-Host (Get-ConsoleText "  - no third-party antivirus detected: the machine will be left without an on-access scanner") -ForegroundColor Red
        }
        Write-Host ""

        $answer = Read-Host (Get-ConsoleText "Type REMOVE to continue, or press Enter to skip")
        return ([string]$answer).Trim() -eq 'REMOVE'
    }

    # ---- GUI path ----
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null
    $usesDarkMode = Get-SystemUsesDarkMode
    $ownerWindow = if ($Owner) { $Owner } else { $script:GuiWindow }

    $overlay = $null
    $overlayWasAlreadyVisible = $false
    if ($ownerWindow) {
        try {
            $overlay = $ownerWindow.FindName('ModalOverlay')
            if ($overlay) {
                $overlayWasAlreadyVisible = ($overlay.Visibility -eq 'Visible')
                if (-not $overlayWasAlreadyVisible) {
                    $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Visible' })
                }
            }
        }
        catch { }
    }

    try {
        $xaml = ConvertTo-LocalizedXaml -Xaml (Get-Content -Path $script:DefenderRemovalConfirmSchema -Raw)
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        try {
            $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
        }
        finally {
            $reader.Close()
        }

        if ($ownerWindow) {
            try { $dialog.Owner = $ownerWindow } catch { }
        }

        Set-WindowThemeResources -window $dialog -usesDarkMode $usesDarkMode

        $bodyText = $dialog.FindName('BodyText')
        $promptText = $dialog.FindName('PromptText')
        $input = $dialog.FindName('ConfirmInput')
        $cancelButton = $dialog.FindName('CancelButton')
        $removeButton = $dialog.FindName('RemoveButton')
        $titleBar = $dialog.FindName('TitleBar')
        $iconText = $dialog.FindName('IconText')

        $iconText.Foreground = $dialog.FindResource('IconErrorColor')

        $bodyLines = @(
            (Get-ConsoleText "- Services, filter and early-launch drivers, policies, scheduled tasks and program folders are deleted."),
            (Get-ConsoleText "- This cannot be undone from this tool. Recovery requires an in-place upgrade or a clean install."),
            (Get-ConsoleText "- A Windows feature upgrade reinstalls Defender, so the removal has to be repeated afterwards."),
            (Get-ConsoleText "- Windows Security will report that no antivirus is active.")
        )
        if (-not $preflight.IsUnprotected) {
            $bodyLines += (Get-ConsoleText "- Third-party antivirus stays active: {0}." -FormatArgs @(($preflight.ThirdPartyAntivirus -join ', ')))
        }
        $bodyText.Text = ($bodyLines -join "`r`n`r`n")

        $input.Text = ''
        $input.Focus() | Out-Null

        $cancelButton.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() })
        $removeButton.Add_Click({
            if ($input.Text.Trim() -eq 'REMOVE') {
                $dialog.Tag = 'Confirm'
                $dialog.Close()
            }
            else {
                $input.BorderBrush = $dialog.FindResource('IconErrorColor')
                $input.SelectAll()
                $input.Focus() | Out-Null
            }
        })
        $input.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Enter') {
                if ($input.Text.Trim() -eq 'REMOVE') {
                    $dialog.Tag = 'Confirm'
                    $dialog.Close()
                }
                else {
                    $input.BorderBrush = $dialog.FindResource('IconErrorColor')
                }
            }
        })
        $titleBar.Add_MouseLeftButtonDown({ $dialog.DragMove() })
        $dialog.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Escape') {
                $dialog.Tag = 'Cancel'
                $dialog.Close()
            }
        })

        $dialog.ShowDialog() | Out-Null
        return ($dialog.Tag -eq 'Confirm')
    }
    catch {
        Write-Warning (Get-ConsoleText "The confirmation dialog could not be shown: {0}" -FormatArgs @($_.Exception.Message))
        return $false
    }
    finally {
        if ($overlay -and -not $overlayWasAlreadyVisible) {
            try { $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' }) } catch { }
        }
    }
}


<#
    .SYNOPSIS
        Runs the Defender removal confirmation when the feature is selected, and drops the feature when
        the user declines.

    .DESCRIPTION
        Called once before the apply phase, from both the GUI and the CLI, so the confirmation never
        runs inside the background apply runspace that owns the progress modal.

    .OUTPUTS
        System.Boolean. $false when the feature was dropped because the user declined.
#>
function Confirm-DefenderRemovalIfSelected {
    param(
        [System.Windows.Window]$Owner = $null
    )

    if (-not $script:Params.ContainsKey('RemoveWindowsDefender')) { return $true }
    if ($script:DefenderRemovalConfirmed) { return $true }

    # Registry export and restore points still make sense in WhatIf, and nothing gets deleted there.
    if ($script:Params.ContainsKey('WhatIf')) {
        $script:DefenderRemovalConfirmed = $true
        return $true
    }

    if ($script:Params.ContainsKey('AcceptDefenderRemovalRisk')) {
        $script:DefenderRemovalConfirmed = $true
        return $true
    }

    if ($script:Params.ContainsKey('Silent')) {
        Write-Warning (Get-ConsoleText "Microsoft Defender Antivirus removal was skipped: unattended runs must pass -AcceptDefenderRemovalRisk to confirm it.")
        $script:Params.Remove('RemoveWindowsDefender')
        return $false
    }

    if (Confirm-DefenderRemoval -Owner $Owner) {
        $script:DefenderRemovalConfirmed = $true
        return $true
    }

    Write-Host (Get-ConsoleText "Microsoft Defender Antivirus removal was skipped.") -ForegroundColor Yellow
    $script:Params.Remove('RemoveWindowsDefender')
    return $false
}
