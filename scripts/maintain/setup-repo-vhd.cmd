@echo off
rem Create the 300 GB dynamic VHD that hosts LineageOS .repo, register a logon
rem task that attaches it automatically, and attach it once now.
rem NOTE: must be CRLF line endings. LF breaks cmd.exe if(...) blocks.
setlocal
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set VHD=E:\WSL\los24-repo.vhdx

echo ============================================================
echo  .repo virtual disk setup
echo  target: %VHD%  (300 GB, expandable)
echo ============================================================
echo.

if not exist "E:\WSL" mkdir "E:\WSL"

if exist "%VHD%" (
    echo [1/3] VHD already exists, skip creation
) else (
    echo [1/3] creating VHD ...
    > "%TEMP%\mkvhd.txt" echo create vdisk file="%VHD%" maximum=307200 type=expandable
    >> "%TEMP%\mkvhd.txt" echo exit
    diskpart /s "%TEMP%\mkvhd.txt"
    if errorlevel 1 (
        echo [ERROR] VHD creation failed
        goto :done
    )
)

echo.
echo [2/3] registering logon task WSL-Repo-VHD ...
schtasks /Create /TN "WSL-Repo-VHD" /SC ONLOGON /RL HIGHEST /F /TR "wsl.exe --mount --vhd %VHD% --bare" >nul 2>&1
if errorlevel 1 (
    echo [WARN] task registration failed; run this script after each boot instead
) else (
    echo [OK] task registered
)

echo.
echo [3/3] attaching now ...
wsl --mount --vhd "%VHD%" --bare
if errorlevel 1 (
    echo [WARN] attach failed - start WSL first, then run this script again
) else (
    echo [OK] attached as block device
)

:done
echo.
echo ============================================================
powershell -NoProfile -Command "'E free: {0:N1} GB' -f ((Get-PSDrive E).Free/1GB)"
echo ============================================================
pause
