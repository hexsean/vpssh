#!/bin/bash
# @name: configure-nezha
# @description: 哪吒探针安全加固（禁用自动更新、远程命令执行）
# @category: 监控
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

SERVICE_FILE="/etc/systemd/system/nezha-agent.service"

# ---- 检测阶段 ----
detect_state() {
    PLAN=()

    if ! systemctl list-unit-files 2>/dev/null | grep -q nezha-agent; then
        print_err "未检测到 nezha-agent 服务"
        exit 1
    fi

    if [[ ! -f "${SERVICE_FILE}" ]]; then
        print_err "未找到服务配置文件: ${SERVICE_FILE}"
        exit 1
    fi

    # 提取当前参数
    CURRENT_SERVER="$(grep "ExecStart" "${SERVICE_FILE}" | grep -o '"-s"[[:space:]]*"[^"]*"' | cut -d'"' -f4)" || true
    CURRENT_PASSWORD="$(grep "ExecStart" "${SERVICE_FILE}" | grep -o '"-p"[[:space:]]*"[^"]*"' | cut -d'"' -f4)" || true

    if [[ -z "${CURRENT_SERVER}" ]] || [[ -z "${CURRENT_PASSWORD}" ]]; then
        print_err "无法从配置中提取服务器地址或密码"
        exit 1
    fi

    # 构建目标配置
    TARGET_EXEC="ExecStart=/opt/nezha/agent/nezha-agent \"-s\" \"${CURRENT_SERVER}\" \"-p\" \"${CURRENT_PASSWORD}\" --disable-auto-update --disable-force-update --disable-command-execute --report-delay 3"
    CURRENT_EXEC="$(grep "^ExecStart=" "${SERVICE_FILE}")"

    if [[ "${CURRENT_EXEC}" != "${TARGET_EXEC}" ]]; then
        PLAN+=("rewrite_service|重写 systemd 服务配置（加固参数）")
    fi
}

# ---- 展示计划 ----
show_plan() {
    print_header "哪吒探针加固计划"

    echo -e "  服务器: ${BOLD}${CURRENT_SERVER}${NC}"
    echo -e "  密码: ${BOLD}${CURRENT_PASSWORD}${NC}"
    echo ""

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "配置已是目标状态，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_change "${desc}"
    done

    echo ""
    echo -e "  加固项:"
    echo -e "    ${GREEN}✓${NC} --disable-auto-update"
    echo -e "    ${GREEN}✓${NC} --disable-force-update"
    echo -e "    ${GREEN}✓${NC} --disable-command-execute"
    echo -e "    ${GREEN}✓${NC} --report-delay 3"
}

# ---- 执行阶段 ----
execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            rewrite_service)
                print_step "备份当前配置..."
                cp "${SERVICE_FILE}" "${SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
                print_ok "已备份"

                print_step "写入加固配置..."
                cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Nezha Agent
ConditionFileIsExecutable=/opt/nezha/agent/nezha-agent

[Service]
StartLimitInterval=5
StartLimitBurst=10
${TARGET_EXEC}
WorkingDirectory=/root
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/nezha-agent

[Install]
WantedBy=multi-user.target
EOF
                print_ok "服务配置已更新"

                print_step "重载 systemd 并重启服务..."
                systemctl daemon-reload
                if systemctl restart nezha-agent; then
                    print_ok "nezha-agent 已重启"
                else
                    print_err "nezha-agent 重启失败"
                fi

                print_step "检查服务状态..."
                systemctl is-active nezha-agent && print_ok "服务运行中" || print_err "服务未运行"
                ;;
        esac
    done
}

# ---- 主流程 ----
detect_state
show_plan
if confirm; then
    execute_plan
    print_header "哪吒探针加固完成"
else
    echo "已取消操作"
fi
