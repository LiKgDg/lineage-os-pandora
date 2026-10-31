@echo off
chcp 65001 >nul
setlocal

rem 需要管理员：压缩 ext4.vhdx 并恢复 .repo 虚拟磁盘挂载
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set VHDX=D:\WSL\Ubuntu-24.04\ext4.vhdx
set REPOVHD=E:\WSL\los24-repo.vhdx
set DISTRO=Ubuntu-24.04

echo ============================================================
echo  1. 关闭 WSL
echo  2. 压缩 ext4.vhdx（回收已删除的 290 GB）
echo  3. 重启 WSL
echo  4. 重新附加 .repo 虚拟磁盘
echo  5. 挂载并校验
echo ============================================================
echo.

echo [1/5] 关闭 WSL...
wsl --shutdown
timeout /t 8 /nobreak >nul

echo.
echo [2/5] 压缩虚拟磁盘（可能需要 10-30 分钟，请勿关闭窗口）...
> "%TEMP%\compact.txt" echo select vdisk file="%VHDX%"
>> "%TEMP%\compact.txt" echo attach vdisk readonly
>> "%TEMP%\compact.txt" echo compact vdisk
>> "%TEMP%\compact.txt" echo detach vdisk
>> "%TEMP%\compact.txt" echo exit
diskpart /s "%TEMP%\compact.txt"
if errorlevel 1 (
    echo [警告] diskpart 返回错误，压缩可能未完成
)

echo.
echo [3/5] 启动 WSL...
wsl -d %DISTRO% -u root -- echo "  WSL 已启动"
timeout /t 5 /nobreak >nul

echo.
echo [4/5] 附加 .repo 虚拟磁盘...
wsl --mount --vhd "%REPOVHD%" --bare
timeout /t 5 /nobreak >nul

echo.
echo [5/5] 挂载并校验...
wsl -d %DISTRO% -u root -- mount -a
wsl -d %DISTRO% -u root -- sh -c "findmnt -no SOURCE,TARGET,FSTYPE /mnt/los24-repo; findmnt -no SOURCE,TARGET,FSTYPE /root/los24/.repo; cd /root/los24 && echo -n 'repo 项目数: ' && /root/repo-tool/repo list 2>/dev/null | wc -l"

echo.
echo ============================================================
for %%A in ("%VHDX%") do echo ext4.vhdx 现在: %%~zA 字节
powershell -NoProfile -Command "'D 盘可用: {0:N1} GB' -f ((Get-PSDrive D).Free/1GB)"
echo ============================================================
echo.
echo 以后每次重启 WSL 后，若 repo 命令报错，重新运行本脚本即可。
echo.
pause
