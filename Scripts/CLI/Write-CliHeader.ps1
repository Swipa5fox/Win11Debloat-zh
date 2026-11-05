# Prints the header for the script
function Write-CliHeader {
    param (
        $title
    )

    $fullTitle = Get-ConsoleText " Win11Debloat Script - {0}" -FormatArgs @($title)

    if ($script:Params.ContainsKey("Sysprep")) {
        $fullTitle = Get-ConsoleText "{0} (Sysprep mode)" -FormatArgs @($fullTitle)
    }
    else {
        $fullTitle = Get-ConsoleText "{0} (User: {1})" -FormatArgs @($fullTitle, (Get-UserName))
    }

    Clear-Host
    Write-Host "-------------------------------------------------------------------------------------------"
    Write-Host $fullTitle
    Write-Host "-------------------------------------------------------------------------------------------"
}
