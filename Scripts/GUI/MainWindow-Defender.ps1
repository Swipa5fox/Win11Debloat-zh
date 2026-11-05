# MainWindow-Defender.ps1
# Windows Defender module: status refresh, removal option and the leftover report.

<#
    .SYNOPSIS
        Refreshes the Defender module's status block from the live machine state.

    .DESCRIPTION
        The module is the only place where Defender is handled in the GUI, so the status has to answer
        the three questions the removal depends on: is Defender still installed (or only residue),
        is tamper protection blocking the removal, and is a third-party antivirus registered. The
        removal checkbox is disabled when nothing is left, because a run would be refused up front.

    .PARAMETER Window
        The main window that owns the module controls.
#>
function Update-DefenderModule {
    param([System.Windows.Window]$Window)

    $stateText = $Window.FindName('DefenderStateText')
    $protectionText = $Window.FindName('DefenderProtectionText')
    $antivirusText = $Window.FindName('DefenderAntivirusText')
    $removeCheckBox = $Window.FindName('DefenderRemoveCheckBox')
    if (-not $stateText) { return }

    $errorBrush = $Window.Resources['ValidationErrorColor']
    $successBrush = $Window.Resources['ValidationSuccessColor']
    $warningBrush = $Window.Resources['AppRecommendationOptionalColor']
    $normalBrush = $Window.Resources['AppFgColor']

    try {
        $preflight = Get-DefenderRemovalPreflight
    }
    catch {
        $stateText.Text = Get-Translation -Key 'DefenderStatusUnavailable' -FormatArgs @($_.Exception.Message)
        $stateText.Foreground = $errorBrush
        return
    }

    if ($preflight.Installed) {
        $stateText.Text = Get-Translation -Key 'DefenderStatusInstalled'
        $stateText.Foreground = $errorBrush
    }
    elseif ($preflight.ResidueOnly) {
        $stateText.Text = Get-Translation -Key 'DefenderStatusResidue' -FormatArgs @($preflight.Residue.Count)
        $stateText.Foreground = $warningBrush
    }
    else {
        $stateText.Text = Get-Translation -Key 'DefenderStatusAbsent'
        $stateText.Foreground = $successBrush
    }

    if (-not $preflight.DefenderPresent) {
        $protectionText.Text = Get-Translation -Key 'DefenderProtectionNotApplicable'
        $protectionText.Foreground = $normalBrush
    }
    elseif ($preflight.TamperProtected) {
        $protectionText.Text = Get-Translation -Key 'DefenderProtectionTamperOn'
        $protectionText.Foreground = $errorBrush
    }
    else {
        $protectionText.Text = Get-Translation -Key 'DefenderProtectionTamperOff'
        $protectionText.Foreground = $normalBrush
    }

    if ($preflight.IsUnprotected) {
        $antivirusText.Text = Get-Translation -Key 'DefenderAntivirusNone'
        $antivirusText.Foreground = $warningBrush
    }
    else {
        $antivirusText.Text = Get-Translation -Key 'DefenderAntivirusDetected' -FormatArgs @(($preflight.ThirdPartyAntivirus -join ', '))
        $antivirusText.Foreground = $normalBrush
    }

    if ($removeCheckBox) {
        if ($preflight.DefenderPresent) {
            $removeCheckBox.IsEnabled = $true
            $removeCheckBox.ToolTip = $null
        }
        else {
            # Nothing left to remove; the preflight would refuse the run with "not present".
            $removeCheckBox.IsChecked = $false
            $removeCheckBox.IsEnabled = $false
            $removeCheckBox.ToolTip = Get-Translation -Key 'DefenderRemovalUnavailableTooltip'
            [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($removeCheckBox, $true)
        }
    }
}

<#
    .SYNOPSIS
        Runs the leftover check and renders its result below the button.

    .DESCRIPTION
        Shows one block per group that still has something in it. A clean result renders a single
        line instead, so a fully removed machine does not produce a list of ninety "OK" rows.

    .PARAMETER Window
        The main window that owns the module controls.
#>
function Show-DefenderModuleVerification {
    param([System.Windows.Window]$Window)

    $summary = $Window.FindName('DefenderVerifySummaryText')
    $panel = $Window.FindName('DefenderVerifyResultsPanel')
    if (-not $summary -or -not $panel) { return }

    $errorBrush = $Window.Resources['ValidationErrorColor']
    $successBrush = $Window.Resources['ValidationSuccessColor']
    $warningBrush = $Window.Resources['AppRecommendationOptionalColor']
    $normalBrush = $Window.Resources['AppFgColor']

    $panel.Children.Clear()
    $summary.Foreground = $normalBrush
    $summary.Text = Get-Translation -Key 'DefenderVerifyRunning'
    Invoke-DoEvents

    try {
        $rows = @(Get-DefenderRemovalReport)
    }
    catch {
        $summary.Text = Get-Translation -Key 'DefenderVerifyFailed' -FormatArgs @($_.Exception.Message)
        $summary.Foreground = $errorBrush
        return
    }

    $failed = @($rows | Where-Object { $_.Status -eq 'Fail' }).Count
    $warned = @($rows | Where-Object { $_.Status -eq 'Warn' }).Count
    $passed = @($rows | Where-Object { $_.Status -eq 'Ok' }).Count

    $summary.Text = Get-Translation -Key 'DefenderVerifySummary' -FormatArgs @($rows.Count, $passed, $warned, $failed)
    if ($failed -gt 0) { $summary.Foreground = $errorBrush }
    elseif ($warned -gt 0) { $summary.Foreground = $warningBrush }
    else { $summary.Foreground = $successBrush }

    $problems = @($rows | Where-Object { $_.Status -ne 'Ok' })
    if ($problems.Count -eq 0) {
        $cleanLine = New-Object System.Windows.Controls.TextBlock
        $cleanLine.Text = Get-Translation -Key 'DefenderVerifyAllPassed'
        $cleanLine.FontSize = 13
        $cleanLine.TextWrapping = 'Wrap'
        $cleanLine.Foreground = $successBrush
        $panel.Children.Add($cleanLine) | Out-Null
        return
    }

    foreach ($group in @($problems | Group-Object -Property Group)) {
        $header = New-Object System.Windows.Controls.TextBlock
        $header.Text = Get-Translation -Key $group.Name
        $header.FontSize = 13
        $header.FontWeight = 'SemiBold'
        $header.Margin = '0,8,0,2'
        $header.Foreground = $normalBrush
        $panel.Children.Add($header) | Out-Null

        foreach ($row in $group.Group) {
            $line = New-Object System.Windows.Controls.TextBlock
            $label = if ($row.Status -eq 'Fail') { Get-Translation -Key 'DefenderCheckFail' } else { Get-Translation -Key 'DefenderCheckWarn' }
            $line.Text = "[{0}] {1}" -f $label, $row.Item
            $line.FontSize = 12
            $line.TextWrapping = 'Wrap'
            $line.Margin = '12,0,0,2'
            $line.Foreground = if ($row.Status -eq 'Fail') { $errorBrush } else { $warningBrush }
            $panel.Children.Add($line) | Out-Null
        }
    }
}
