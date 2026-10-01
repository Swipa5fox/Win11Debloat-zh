@echo off
setlocal

:: Set Windows Terminal installation paths. (Default and Scoop installation)
set "wtDefaultPath=%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe"
set "wtScoopPath=%USERPROFILE%\scoop\apps\windows-terminal\current\wt.exe"
set "logFile=%~dp0Logs\Win11Debloat-Run.log"

:: Ensure Logs folder exists
if not exist "%~dp0Logs" mkdir "%~dp0Logs"

:: Console text follows the system UI language: a Chinese install gets Chinese prompts, every other
:: locale keeps the original English ones. These are read before the branches below, which expand
:: them while the whole block is parsed.
set "localeName="
for /f "tokens=3" %%a in ('reg query "HKCU\Control Panel\International" /v LocaleName 2^>nul') do set "localeName=%%a"

set "msgTerminalMissing=Windows Terminal not found, using default PowerShell..."
set "msgSupport=If you need further assistance, please open an issue at:"
set "msgLogged=Logged in "
set "msgError=ERROR: "
set "msgFailed=PowerShell command failed"

echo %localeName% | findstr /i /b /c:"zh" >nul
if not errorlevel 1 (
    set "msgTerminalMissing=未找到 Windows Terminal，改用默认 PowerShell 启动..."
    set "msgSupport=如需进一步帮助，请在以下地址提交 issue："
    set "msgLogged=日志已保存到 "
    set "msgError=错误："
    set "msgFailed=PowerShell 命令执行失败"
)

:: Determine which terminal exists
if exist "%wtDefaultPath%" (
    set "wtPath=%wtDefaultPath%"
) else if exist "%wtScoopPath%" (
    set "wtPath=%wtScoopPath%"
) else (
    set "wtPath="
)

:: Interpolated into a PS single-quoted string below;
:: Apostrophes escaped via %:'=''% and -File arg uses [char]34 to avoid quote-parity bugs.
set "SCRIPT_PATH=%~dp0Win11Debloat.ps1"

if defined wtPath (
    call :Log Launching Win11Debloat.ps1 with Windows Terminal...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$p='%SCRIPT_PATH:'=''%'; $w='%wtPath:'=''%'; $q=[char]34; Start-Process -FilePath $w -ArgumentList ('PowerShell -NoProfile -ExecutionPolicy Bypass -File ' + $q + $p + $q) -Verb RunAs" >> "%logFile%" || call :Error "%msgFailed%"
) else (
    echo %msgTerminalMissing%
    call :Log Windows Terminal not found. Using default PowerShell to launch Win11Debloat.ps1...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$p='%SCRIPT_PATH:'=''%'; $q=[char]34; Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + $q + $p + $q) -Verb RunAs" >> "%logFile%" || call :Error "%msgFailed%"
)

echo.
echo %msgSupport%
echo https://github.com/Raphire/Win11Debloat/issues
goto :EOF

:: Logging Function
:Log
echo(%* >> "%logFile%"
goto :EOF

:: Error Handler
:Error
echo(%msgError%%~1
call :Log ERROR: %*
echo %msgLogged%%logFile%
pause
goto :EOF
