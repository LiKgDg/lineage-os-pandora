@echo off
chcp 65001 >nul
setlocal

rem 需要管理员权限：自动提权重启自身
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在请求管理员权限...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo  为 LineageOS 源码树的 .repo 创建独立虚拟磁盘
echo  目标: E:\WSL\los24-repo.vhdx  300 GB 动态扩展
echo  作用: 把 290 GB 的 git 对象库移出 D 盘
echo ============================================================
echo.

if not exist "E:\WSL" mkdir "E:\WSL"

if exist "E:\WSL\los24-repo.vhdx" (
    echo [跳过] VHD 已存在
) else (
    echo [1/3] 创建 VHD...
    > "%TEMP%\mkvhd.txt" echo create vdisk file="E:\WSL\los24-repo.vhdx" maximum=307200 type=expandable
    >> "%TEMP%\mkvhd.txt" echo exit
    diskpart /s "%TEMP%\mkvhd.txt"
    if errorlevel 1 (
        echo [失败] VHD 创建失败
        pause
        exit /b 1
    )
)

echo.
echo [2/3] 注册登录时自动挂载的计划任务...
schtasks /Create /TN "WSL-Repo-VHD" /SC ONLOGON /RL HIGHEST /F ^
  /TR "wsl.exe --mount --vhd E:\WSL\los24-repo.vhdx --bare" >nul 2>&1
if errorlevel 1 (
    echo [警告] 计划任务注册失败，以后需手动运行本脚本挂载
) else (
    echo [成功] 已注册 WSL-Repo-VHD，登录时自动挂载
)

echo.
echo [3/3] 立即挂载一次...
wsl.exe --mount --vhd E:\WSL\los24-repo.vhdx --bare
if errorlevel 1 (
    echo [警告] 挂载失败，可能 WSL 未运行。稍后可再运行本脚本重试
) else (
    echo [成功] 已挂载为块设备
)

echo.
echo ============================================================
if exist "E:\WSL\los24-repo.vhdx" (
    for %%A in ("E:\WSL\los24-repo.vhdx") do echo VHD 大小: %%~zA 字节
)
echo E 盘可用空间:
powershell -NoProfile -Command "'{0:N1} GB' -f ((Get-PSDrive E).Free/1GB)"
echo ============================================================
echo.
echo 完成后回到对话告诉我，我继续做格式化和数据迁移。
echo.
pause
