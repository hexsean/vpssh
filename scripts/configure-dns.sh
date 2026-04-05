#!/bin/bash
# @name: configure-dns
# @description: DNS 解析检测与优化（测试多 DNS 服务器，可切换配置）
# @category: 网络
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

DNS_SYSTEM=""
CLOUD_ENV=""
MAIN_INTERFACE=""
PRIMARY_DNS=""
SECONDARY_DNS=""
DNS_PROVIDER=""

# ---- 检测 DNS 环境 ----
detect_dns_system() {
    print_header "检测 DNS 环境"

    if systemctl is-active systemd-resolved &>/dev/null; then
        DNS_SYSTEM="systemd-resolved"
        print_ok "系统使用 systemd-resolved"
    elif [[ -L /etc/resolv.conf ]] && [[ "$(readlink /etc/resolv.conf)" == */NetworkManager/* ]]; then
        DNS_SYSTEM="networkmanager"
        print_ok "系统使用 NetworkManager"
    else
        DNS_SYSTEM="traditional"
        print_ok "系统使用传统 /etc/resolv.conf"
    fi

    # 当前 DNS
    echo -e "\n当前 DNS 服务器:"
    if [[ "${DNS_SYSTEM}" == "systemd-resolved" ]] && has_cmd resolvectl; then
        resolvectl status 2>/dev/null | grep "DNS Server" || true
    else
        grep "nameserver" /etc/resolv.conf || true
    fi

    # 主网络接口
    MAIN_INTERFACE="$(ip route | grep default | awk '{print $5}' | head -n 1)" || true
    if [[ -n "${MAIN_INTERFACE}" ]]; then
        print_ok "主网络接口: ${MAIN_INTERFACE}"
    else
        print_warn "无法自动检测网络接口"
        read -r -p "请输入网络接口名称 (如 ens5, eth0): " MAIN_INTERFACE </dev/tty
    fi

    # 云环境
    if curl -s --connect-timeout 1 --max-time 1 http://100.100.100.200/latest/meta-data/ &>/dev/null; then
        CLOUD_ENV="alicloud"
        print_ok "检测到阿里云环境"
    elif curl -s --connect-timeout 1 --max-time 1 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        CLOUD_ENV="aws"
        print_ok "检测到 AWS 环境"
    else
        CLOUD_ENV="unknown"
        print_ok "未检测到已知云环境"
    fi
}

# ---- 测试 DNS 解析（只读操作） ----
test_dns_resolution() {
    print_header "DNS 解析测试"

    local test_domain="www.google-analytics.com"

    if ! has_cmd dig; then
        print_warn "未找到 dig，需要安装 dnsutils 才能测试"
        if confirm "是否安装 dnsutils？"; then
            apt update -qq && apt install -y dnsutils > /dev/null 2>&1 || true
        fi
    fi

    if ! has_cmd dig; then
        print_warn "dig 不可用，跳过 DNS 测试"
        return
    fi

    local servers=("8.8.8.8|Google DNS" "1.1.1.1|Cloudflare DNS")
    if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
        servers+=("100.100.2.136|阿里云内网 DNS")
    fi

    for entry in "${servers[@]}"; do
        local ip="${entry%%|*}"
        local name="${entry##*|}"
        echo -e "\n  ${BOLD}${name}${NC} (${ip}):"
        local result
        result="$(dig +short "${test_domain}" @"${ip}" 2>/dev/null)" || true
        if [[ -z "${result}" ]]; then
            print_err "  无法解析"
        else
            echo -e "    解析结果: ${BLUE}${result}${NC}"
        fi
    done
}

read_custom_dns() {
    read -r -p "主 DNS: " PRIMARY_DNS </dev/tty
    read -r -p "辅助 DNS: " SECONDARY_DNS </dev/tty
    DNS_PROVIDER="自定义"
}

select_dns() {
    print_header "选择 DNS 服务器"
    while true; do
        echo -e "  ${BOLD}1)${NC} Cloudflare DNS (1.1.1.1, 1.0.0.1)"
        echo -e "  ${BOLD}2)${NC} Google DNS (8.8.8.8, 8.8.4.4)"
        if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
            echo -e "  ${BOLD}3)${NC} 阿里云内网 DNS (100.100.2.136, 100.100.2.138)"
            echo -e "  ${BOLD}4)${NC} 自定义"
            echo -e "  ${BOLD}0)${NC} 退出"
        else
            echo -e "  ${BOLD}3)${NC} 自定义"
            echo -e "  ${BOLD}0)${NC} 退出"
        fi

        read -r -p "$(echo -e "\n${CYAN}请选择: ${NC}")" choice </dev/tty
        case "${choice}" in
            1) PRIMARY_DNS="1.1.1.1"; SECONDARY_DNS="1.0.0.1"; DNS_PROVIDER="Cloudflare"; return ;;
            2) PRIMARY_DNS="8.8.8.8"; SECONDARY_DNS="8.8.4.4"; DNS_PROVIDER="Google"; return ;;
            3)
                if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
                    PRIMARY_DNS="100.100.2.136"; SECONDARY_DNS="100.100.2.138"; DNS_PROVIDER="阿里云内网"; return
                else
                    read_custom_dns; return
                fi
                ;;
            4)
                if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
                    read_custom_dns; return
                else
                    print_err "无效选项"
                fi
                ;;
            0) echo "退出"; exit 0 ;;
            *) print_err "无效选项，请重试" ;;
        esac
    done
}

# ---- 展示并确认 DNS 变更计划 ----
show_dns_plan() {
    print_header "DNS 变更计划"
    print_plan_change "DNS 提供商: ${DNS_PROVIDER}"
    print_plan_change "主 DNS: ${PRIMARY_DNS}"
    print_plan_change "辅 DNS: ${SECONDARY_DNS}"
    print_plan_change "配置方式: ${DNS_SYSTEM}"
}

# ---- 应用 DNS ----
apply_dns() {
    case "${DNS_SYSTEM}" in
        systemd-resolved)
            if has_cmd resolvectl; then
                print_step "通过 resolvectl 配置 DNS..."
                if resolvectl dns "${MAIN_INTERFACE}" "${PRIMARY_DNS}" "${SECONDARY_DNS}"; then
                    systemctl restart systemd-resolved
                    print_ok "systemd-resolved 已更新"
                else
                    print_warn "resolvectl 失败，回退到配置文件方式..."
                    apply_resolved_conf
                fi
            else
                apply_resolved_conf
            fi
            ;;
        networkmanager)
            if has_cmd nmcli; then
                local conn
                conn="$(nmcli -g NAME con show --active | head -n 1)" || true
                if [[ -n "${conn}" ]]; then
                    print_step "通过 NetworkManager 配置 DNS..."
                    nmcli con mod "${conn}" ipv4.dns "${PRIMARY_DNS} ${SECONDARY_DNS}"
                    nmcli con up "${conn}"
                    print_ok "NetworkManager 已更新"
                else
                    apply_resolv_conf
                fi
            else
                apply_resolv_conf
            fi
            ;;
        *)
            apply_resolv_conf
            ;;
    esac
}

apply_resolved_conf() {
    print_step "写入 /etc/systemd/resolved.conf..."
    [[ -f /etc/systemd/resolved.conf ]] && cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=${PRIMARY_DNS} ${SECONDARY_DNS}
FallbackDNS=
EOF
    systemctl restart systemd-resolved
    print_ok "resolved.conf 已更新"
}

apply_resolv_conf() {
    print_step "写入 /etc/resolv.conf..."
    [[ -f /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]] && cp /etc/resolv.conf /etc/resolv.conf.bak
    [[ -L /etc/resolv.conf ]] && rm /etc/resolv.conf

    local content="# Managed by vpssh configure-dns
nameserver ${PRIMARY_DNS}"
    [[ -n "${SECONDARY_DNS}" ]] && content="${content}
nameserver ${SECONDARY_DNS}"
    content="${content}
options edns0"
    echo "${content}" > /etc/resolv.conf
    print_ok "/etc/resolv.conf 已更新"
}

# ---- 验证 ----
verify_dns() {
    print_header "验证新 DNS"
    sleep 1
    for domain in "www.google.com" "youtube.com"; do
        local result
        result="$(dig +short "${domain}" 2>/dev/null)" || true
        if [[ -n "${result}" ]]; then
            print_ok "${domain} → ${result}"
        else
            print_err "${domain} 解析失败"
        fi
    done
}

# ---- 主流程 ----
detect_dns_system
test_dns_resolution
select_dns
show_dns_plan
if confirm; then
    apply_dns
    verify_dns
    print_header "DNS 配置完成"
    echo -e "恢复方法:"
    echo -e "  systemd-resolved: ${CYAN}cp /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf && systemctl restart systemd-resolved${NC}"
    echo -e "  传统方式: ${CYAN}cp /etc/resolv.conf.bak /etc/resolv.conf${NC}"
else
    echo "已取消操作"
fi
