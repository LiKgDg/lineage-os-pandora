@echo off
rem Compact the WSL distro vhdx (reclaims space deleted inside Linux) and
rem re-attach the .repo VHD afterwards.
rem NOTE: must be CRLF line endings. LF breaks cmd.exe if(...) blocks.
setlocal
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set DISTRO=Ubuntu-24.04
set VHDX=D:\WSL\Ubuntu-24.04\ext4.vhdx
set REPOVHD=E:\WSL\los24-repo.vhdx

echo ============================================================
echo  [1/5] shutdown WSL
echo  [2/5] compact ext4.vhdx  (10-30 min, keep this window open)
echo  [3/5] start WSL
echo  [4/5] re-attach .repo VHD
echo  [5/5] mount and verify
echo ============================================================
echo.

echo [1/5] shutting down WSL ...
wsl --shutdown
timeout /t 10 /nobreak >nul

echo.
echo [2/5] compacting ...
> "%TEMP%\compact.txt" echo select vdisk file="%VHDX%"
>> "%TEMP%\compact.txt" echo attach vdisk readonly
>> "%TEMP%\compact.txt" echo compact vdisk
>> "%TEMP%\compact.txt" echo detach vdisk
>> "%TEMP%\compact.txt" echo exit
diskpart /s "%TEMP%\compact.txt"

echo.
echo [3/5] starting WSL ...
wsl -d %DISTRO% -u root -- echo "  started"
timeout /t 6 /nobreak >nul

echo.
echo [4/5] attaching .repo VHD ...
if exist "%REPOVHD%" (
    wsl --mount --vhd "%REPOVHD%" --bare
    timeout /t 6 /nobreak >nul
) else (
    echo [WARN] %REPOVHD% not found, skipped
)

echo.
echo [5/5] mounting and verifying ...
wsl -d %DISTRO% -u root -- mount -a
wsl -d %DISTRO% -u root -- sh -c "findmnt -no SOURCE,TARGET /root/los24/.repo; cd /root/los24 && echo -n 'repo projects: ' && /root/repo-tool/repo list 2>/dev/null | wc -l"

echo.
echo ============================================================
for %%A in ("%VHDX%") do echo ext4.vhdx: %%~zA bytes
powershell -NoProfile -Command "'D free: {0:N1} GB' -f ((Get-PSDrive D).Free/1GB)"
echo ============================================================
pause
