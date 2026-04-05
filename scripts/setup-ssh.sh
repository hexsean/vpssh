#!/bin/bash
# @name: setup-ssh
# @description: SSH 密钥认证加固（禁用密码登录、更改端口、配置 UFW 防火墙）
# @category: 安全
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

SSH_PORT="22088"
SSHD_CONF="/etc/ssh/sshd_config.d/hardened.conf"
AUTH_KEYS="/root/.ssh/authorized_keys"
KEEP_EXISTING_PUBKEY=false
SSH_PUBKEY=""
UFW_STATUS=""
OLD_CONFS=()

TARGET_SSHD_CONTENT="# Managed by vpssh setup-ssh
Port ${SSH_PORT}
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys"

collect_pubkey() {
    print_header "SSH 公钥"
    if [[ -f "${AUTH_KEYS}" ]] && [[ -s "${AUTH_KEYS}" ]]; then
        echo -e "当前已有公钥:"
        echo -e "${DIM}$(cat "${AUTH_KEYS}")${NC}"
        echo ""
        read -r -p "$(echo -e "${YELLOW}是否替换为新公钥？[y/N]: ${NC}")" replace </dev/tty
        if [[ ! "${replace}" =~ ^[Yy]$ ]]; then
            KEEP_EXISTING_PUBKEY=true
            return
        fi
    fi

    echo -e "请粘贴你的 SSH 公钥（ssh-rsa/ssh-ed25519 ...）："
    read -r SSH_PUBKEY </dev/tty

    if [[ -z "${SSH_PUBKEY}" ]]; then
        print_err "公钥不能为空"
        exit 1
    fi

    if [[ ! "${SSH_PUBKEY}" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        print_warn "公钥格式看起来不对，请确认是否正确"
        if ! confirm "仍然继续？"; then
            exit 1
        fi
    fi
}

detect_state() {
    PLAN=()

    if [[ ! -d "/root/.ssh" ]] || [[ "$(stat -c '%a' /root/.ssh 2>/dev/null)" != "700" ]]; then
        PLAN+=("fix_ssh_dir|创建/修复 ~/.ssh 目录权限 (700)")
    fi

    if [[ "${KEEP_EXISTING_PUBKEY}" == "false" ]]; then
        PLAN+=("write_pubkey|写入 SSH 公钥到 authorized_keys")
    fi

    if [[ ! -d "/etc/ssh/sshd_config.d" ]]; then
        PLAN+=("create_sshd_dir|创建 /etc/ssh/sshd_config.d 目录")
    fi

    # 收集旧配置文件列表（detect 和 execute 共用）
    OLD_CONFS=()
    for conf in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "${conf}" ]] || continue
        if [[ "${conf}" != "${SSHD_CONF}" ]]; then
            OLD_CONFS+=("${conf}")
        fi
    done
    if [[ ${#OLD_CONFS[@]} -gt 0 ]]; then
        PLAN+=("clean_old_conf|清理 sshd_config.d 下的旧配置文件")
    fi

    if ! file_matches "${SSHD_CONF}" "${TARGET_SSHD_CONTENT}"; then
        PLAN+=("write_sshd_conf|写入 SSH 加固配置 (端口 ${SSH_PORT}，禁用密码)")
    fi

    if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
        PLAN+=("add_include|添加 Include 指令到 sshd_config")
    fi

    # 需要重启 sshd 的条件
    local has_sshd_change=false
    for item in "${PLAN[@]}"; do
        if [[ "${item}" =~ (write_sshd_conf|clean_old_conf|add_include) ]]; then
            has_sshd_change=true
            break
        fi
    done
    if [[ "${has_sshd_change}" == "true" ]]; then
        PLAN+=("restart_sshd|重启 sshd 服务")
    fi

    # 缓存 ufw status 避免重复调用
    if has_cmd ufw; then
        UFW_STATUS="$(ufw status 2>/dev/null)"
        if ! echo "${UFW_STATUS}" | grep -q "${SSH_PORT}/tcp.*ALLOW"; then
            PLAN+=("ufw_allow|UFW 放行端口 ${SSH_PORT}/tcp")
        fi
        if echo "${UFW_STATUS}" | grep -q "22/tcp.*ALLOW"; then
            PLAN+=("ufw_deny_22|UFW 移除默认 22 端口规则")
        fi
    else
        PLAN+=("install_ufw|安装并配置 UFW 防火墙")
    fi
}

show_plan() {
    print_header "SSH 加固配置计划"

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "SSH 已完全加固，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_add "${desc}"
    done

    if [[ -d "/root/.ssh" ]] && [[ "$(stat -c '%a' /root/.ssh 2>/dev/null)" == "700" ]]; then
        print_plan_skip "~/.ssh 目录权限正确"
    fi
    if [[ "${KEEP_EXISTING_PUBKEY}" == "true" ]]; then
        print_plan_skip "authorized_keys 保持不变"
    fi
    if file_matches "${SSHD_CONF}" "${TARGET_SSHD_CONTENT}"; then
        print_plan_skip "SSH 配置已是目标状态"
    fi
    if [[ -n "${UFW_STATUS}" ]] && echo "${UFW_STATUS}" | grep -q "${SSH_PORT}/tcp.*ALLOW"; then
        print_plan_skip "UFW 已放行 ${SSH_PORT}"
    fi

    echo ""
    print_warn "请确保你有可用的 SSH 密钥，否则将无法登录！"
}

execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            fix_ssh_dir)
                print_step "修复 ~/.ssh 目录..."
                mkdir -p /root/.ssh
                chmod 700 /root/.ssh
                print_ok "~/.ssh 权限已设为 700"
                ;;
            write_pubkey)
                print_step "写入公钥..."
                mkdir -p "$(dirname "${AUTH_KEYS}")"
                echo "${SSH_PUBKEY}" > "${AUTH_KEYS}"
                chmod 600 "${AUTH_KEYS}"
                print_ok "公钥已写入 authorized_keys"
                ;;
            create_sshd_dir)
                print_step "创建 sshd_config.d..."
                mkdir -p /etc/ssh/sshd_config.d
                print_ok "目录已创建"
                ;;
            clean_old_conf)
                print_step "清理旧配置文件..."
                for conf in "${OLD_CONFS[@]}"; do
                    rm -f "${conf}"
                    print_ok "已删除: ${conf}"
                done
                ;;
            write_sshd_conf)
                print_step "写入 SSH 加固配置..."
                write_file_if_changed "${SSHD_CONF}" "${TARGET_SSHD_CONTENT}"
                ;;
            add_include)
                print_step "添加 Include 指令..."
                echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
                print_ok "Include 指令已添加"
                ;;
            restart_sshd)
                print_step "重启 sshd..."
                if systemctl restart sshd; then
                    print_ok "sshd 已重启"
                else
                    print_err "sshd 重启失败，请手动检查"
                fi
                ;;
            install_ufw)
                print_step "安装 UFW..."
                apt update -y && apt install -y ufw
                ufw --force enable
                ufw allow "${SSH_PORT}/tcp"
                ufw delete allow 22/tcp 2>/dev/null || true
                print_ok "UFW 已安装并配置"
                ;;
            ufw_allow)
                print_step "UFW 放行端口 ${SSH_PORT}..."
                ufw allow "${SSH_PORT}/tcp"
                print_ok "已放行 ${SSH_PORT}/tcp"
                ;;
            ufw_deny_22)
                print_step "UFW 移除 22 端口..."
                ufw delete allow 22/tcp 2>/dev/null || true
                print_ok "已移除 22/tcp 规则"
                ;;
        esac
    done

    print_header "SSH 加固完成"
    echo -e "  ${GREEN}✓${NC} SSH 端口: ${BOLD}${SSH_PORT}${NC}"
    echo -e "  ${GREEN}✓${NC} 密码登录: ${BOLD}已禁用${NC}"
    echo -e "  ${GREEN}✓${NC} 认证方式: ${BOLD}仅密钥${NC}"
    echo ""
    print_warn "请用新端口测试连接，确认正常前不要关闭当前会话！"
}

collect_pubkey
detect_state
show_plan
if confirm; then
    execute_plan
else
    echo "已取消操作"
fi
