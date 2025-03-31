#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# 封装打印函数
print_header() {
    echo -e "\n${BOLD}${UNDERLINE}$1${NC}\n"
}

print_subheader() {
    echo -e "${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_prompt() {
    echo -e "${CYAN}$1${NC}"
}

# 确保脚本以root权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${RED}此脚本需要root权限，请使用sudo运行${NC}"
   exit 1
fi

# 清屏并显示标题
clear
echo -e "${BOLD}${BLUE}=================================${NC}"
echo -e "${BOLD}${BLUE}      DNS配置检测与优化工具      ${NC}"
echo -e "${BOLD}${BLUE}=================================${NC}"
echo ""

# 检测当前系统使用的DNS解析方案
check_dns_system() {
    print_header "检测当前DNS环境"

    # 检查是否使用systemd-resolved
    if systemctl is-active systemd-resolved &>/dev/null; then
        print_info "- 系统使用systemd-resolved服务管理DNS"
        DNS_SYSTEM="systemd-resolved"
    elif [ -L /etc/resolv.conf ] && [ "$(readlink /etc/resolv.conf)" == "/run/systemd/resolve/stub-resolv.conf" ]; then
        print_info "- 系统使用systemd-resolved (stub resolver)"
        DNS_SYSTEM="systemd-resolved"
    elif [ -L /etc/resolv.conf ] && [[ "$(readlink /etc/resolv.conf)" == */NetworkManager/* ]]; then
        print_info "- 系统使用NetworkManager管理DNS"
        DNS_SYSTEM="networkmanager"
    else
        print_info "- 系统使用传统方式管理DNS (/etc/resolv.conf)"
        DNS_SYSTEM="traditional"
    fi

    # 显示当前DNS服务器
    print_subheader "当前DNS服务器配置:"
    if [ "$DNS_SYSTEM" == "systemd-resolved" ] && command -v resolvectl &>/dev/null; then
        resolvectl status | grep "DNS Server"
    else
        grep "nameserver" /etc/resolv.conf
    fi

    # 检测主网络接口
    print_subheader "检测主网络接口..."
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -n "$DEFAULT_IFACE" ]; then
        print_info "- 主网络接口: ${BOLD}$DEFAULT_IFACE${NC}"
        MAIN_INTERFACE="$DEFAULT_IFACE"
    else
        print_warning "- 无法检测到默认网络接口，请手动指定"
        print_prompt "请输入网络接口名称 (如ens5, eth0): "
        read MAIN_INTERFACE
    fi

    # 检测云环境
    print_subheader "检测云环境..."
    if curl -s --connect-timeout 2 --max-time 3 http://100.100.100.200/latest/meta-data/ &>/dev/null; then
        print_info "- 检测到阿里云环境"
        CLOUD_ENV="alicloud"
        # 获取区域信息
        REGION=$(curl -s http://100.100.100.200/latest/meta-data/region-id 2>/dev/null)
        if [ -n "$REGION" ]; then
            print_info "- 阿里云区域: ${BOLD}$REGION${NC}"
        fi
    elif curl -s --connect-timeout 2 --max-time 3 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        print_info "- 检测到AWS或类似云环境"
        CLOUD_ENV="aws"
    else
        print_info "- 未检测到已知云环境特征"
        CLOUD_ENV="unknown"
    fi

    echo ""
}

# 测试不同DNS服务器的解析结果
test_dns_resolution() {
    print_header "测试不同DNS服务器的解析结果"
    print_info "这将帮助判断当前环境是否存在DNS解析问题"
    echo ""

    TEST_DOMAIN="www.google-analytics.com"

    # 创建临时结果存储
    TEMP_FILE=$(mktemp)

    # 检查是否安装了dig
    if ! command -v dig &>/dev/null; then
        print_warning "未找到dig命令，正在尝试安装..."
        if command -v apt &>/dev/null; then
            apt update -qq && apt install -y dnsutils > /dev/null
        elif command -v yum &>/dev/null; then
            yum install -y bind-utils > /dev/null
        elif command -v dnf &>/dev/null; then
            dnf install -y bind-utils > /dev/null
        else
            print_error "无法安装dig，请手动安装后再运行此脚本"
            return 1
        fi
    fi

    # 测试函数
    test_single_dns() {
        local dns_server="$1"
        local dns_name="$2"
        print_subheader "测试 ${BOLD}$dns_name${NC} (${BLUE}$dns_server${NC}):"

        # 执行DNS查询
        local result=$(dig +short "$TEST_DOMAIN" @"$dns_server" 2>/dev/null)

        if [ -z "$result" ]; then
            print_error "  未能解析域名，可能无法访问此DNS服务器"
            return
        fi

        echo -e "  解析结果: ${BLUE}$result${NC}"

        # 反向解析检查是否是谷歌日本区域节点
        for ip in $result; do
            local reverse=$(dig +short -x "$ip" 2>/dev/null)
            if [ -n "$reverse" ]; then
                echo -e "  反向解析: ${BLUE}$reverse${NC}"
                if [[ "$reverse" == *"nrt"*".1e100.net"* ]]; then
                    print_success "  解析到了谷歌日本节点 (推荐)"
                    echo "$dns_server - $dns_name: 日本节点 ($reverse)" >> "$TEMP_FILE"
                elif [[ "$reverse" == *".1e100.net"* ]]; then
                    print_success "  解析到了谷歌全球节点"
                    echo "$dns_server - $dns_name: 全球节点 ($reverse)" >> "$TEMP_FILE"
                elif [[ "$ip" == "203.208"* ]]; then
                    print_error "  解析到了谷歌北京节点 (不推荐)"
                    echo "$dns_server - $dns_name: 北京节点 ($ip)" >> "$TEMP_FILE"
                else
                    echo -e "  ${YELLOW}? 未知区域节点${NC}"
                    echo "$dns_server - $dns_name: 未知节点 ($ip)" >> "$TEMP_FILE"
                fi
            else
                if [[ "$ip" == "203.208"* ]]; then
                    print_error "  解析到了谷歌北京节点 (不推荐)"
                    echo "$dns_server - $dns_name: 北京节点 ($ip)" >> "$TEMP_FILE"
                else
                    echo -e "  ${YELLOW}? 无法反向解析此IP: $ip${NC}"
                    echo "$dns_server - $dns_name: 未知 ($ip)" >> "$TEMP_FILE"
                fi
            fi
        done

        echo ""
    }

    # 测试各种DNS
    test_single_dns "8.8.8.8" "Google DNS"
    test_single_dns "8.8.4.4" "Google DNS(备用)"
    test_single_dns "1.1.1.1" "Cloudflare DNS"
    test_single_dns "1.0.0.1" "Cloudflare DNS(备用)"

    # 如果处于阿里云环境，测试阿里云内网DNS
    if [ "$CLOUD_ENV" == "alicloud" ]; then
        test_single_dns "100.100.2.136" "阿里云内网DNS"
        test_single_dns "100.100.2.138" "阿里云内网DNS(备用)"
    fi

    # 测试当前系统DNS
    CURRENT_DNS=$(grep -m1 "nameserver" /etc/resolv.conf | awk '{print $2}')
    if [ -n "$CURRENT_DNS" ] && [ "$CURRENT_DNS" != "127.0.0.53" ]; then
        test_single_dns "$CURRENT_DNS" "当前系统DNS"
    fi

    # 总结结果
    print_header "DNS解析测试结果摘要"
    echo -e "${BLUE}--------------------${NC}"
    if grep -q "北京节点" "$TEMP_FILE"; then
        print_warning "检测到部分DNS将谷歌域名解析到北京节点，这可能导致访问缓慢"
        print_info "推荐使用以下DNS服务器之一:"
        grep "日本节点\|全球节点" "$TEMP_FILE" | cut -d':' -f1 | sed 's/^/  /' | sed -e "s/^/  ${GREEN}/" -e "s/$/${NC}/"
    else
        print_success "所有测试的DNS均未将谷歌域名解析到北京节点"
    fi

    # 清理临时文件
    rm -f "$TEMP_FILE"

    echo ""
}

# 提供DNS选项让用户选择
select_dns() {
    print_header "DNS服务器选择"
    print_prompt "是否需要更改DNS服务器配置?"
    echo -e "${BOLD}1)${NC} 是，我想更改DNS配置"
    echo -e "${BOLD}2)${NC} 否，保持当前配置"
    print_prompt "请选择 [1-2]: "
    read change_dns

    if [ "$change_dns" != "1" ]; then
        print_info "保持当前DNS配置，退出脚本"
        exit 0
    fi

    print_subheader "请选择DNS服务器:"
    echo -e "${BOLD}1)${NC} ${CYAN}Cloudflare DNS${NC} (1.1.1.1, 1.0.0.1) - 推荐用于阿里云环境"
    echo -e "${BOLD}2)${NC} ${CYAN}Google DNS${NC} (8.8.8.8, 8.8.4.4)"

    if [ "$CLOUD_ENV" == "alicloud" ]; then
        echo -e "${BOLD}3)${NC} ${CYAN}阿里云内网DNS${NC} (100.100.2.136, 100.100.2.138) - 适合阿里云环境"
        echo -e "${BOLD}4)${NC} 自定义DNS"
        echo -e "${BOLD}5)${NC} 退出"
        max_option=5
    else
        echo -e "${BOLD}3)${NC} 自定义DNS"
        echo -e "${BOLD}4)${NC} 退出"
        max_option=4
    fi

    print_prompt "请输入选项[1-$max_option]: "
    read dns_option

    case $dns_option in
        1)
            PRIMARY_DNS="1.1.1.1"
            SECONDARY_DNS="1.0.0.1"
            DNS_PROVIDER="Cloudflare DNS"
            ;;
        2)
            PRIMARY_DNS="8.8.8.8"
            SECONDARY_DNS="8.8.4.4"
            DNS_PROVIDER="Google DNS"
            ;;
        3)
            if [ "$CLOUD_ENV" == "alicloud" ]; then
                PRIMARY_DNS="100.100.2.136"
                SECONDARY_DNS="100.100.2.138"
                DNS_PROVIDER="阿里云内网DNS"
            else
                print_prompt "请输入主DNS服务器: "
                read PRIMARY_DNS
                print_prompt "请输入辅助DNS服务器(可选): "
                read SECONDARY_DNS
                DNS_PROVIDER="自定义DNS"
            fi
            ;;
        4)
            if [ "$CLOUD_ENV" == "alicloud" ]; then
                print_prompt "请输入主DNS服务器: "
                read PRIMARY_DNS
                print_prompt "请输入辅助DNS服务器(可选): "
                read SECONDARY_DNS
                DNS_PROVIDER="自定义DNS"
            else
                print_info "退出脚本"
                exit 0
            fi
            ;;
        5)
            if [ "$max_option" -eq 5 ]; then
                print_info "退出脚本"
                exit 0
            else
                print_error "无效选项，请重试"
                select_dns
            fi
            ;;
        *)
            print_error "无效选项，请重试"
            select_dns
            ;;
    esac
}

# 应用DNS配置
apply_dns() {
    print_header "应用DNS配置"
    print_info "正在应用 ${BOLD}$DNS_PROVIDER${NC} (${CYAN}$PRIMARY_DNS, $SECONDARY_DNS${NC})..."

    # 根据系统使用不同的方式配置DNS
    case $DNS_SYSTEM in
        systemd-resolved)
            print_info "检测到systemd-resolved服务，尝试配置..."

            # 尝试使用resolvectl
            if command -v resolvectl &>/dev/null; then
                print_info "使用resolvectl配置接口 ${BOLD}$MAIN_INTERFACE${NC} 的DNS..."
                resolvectl dns "$MAIN_INTERFACE" "$PRIMARY_DNS" "$SECONDARY_DNS"
                if [ $? -eq 0 ]; then
                    systemctl restart systemd-resolved
                    print_success "成功配置systemd-resolved使用新的DNS"
                else
                    print_error "使用resolvectl配置失败，尝试修改配置文件..."
                    modify_resolved_conf
                fi
            else
                print_warning "未找到resolvectl命令，尝试修改配置文件..."
                modify_resolved_conf
            fi
            ;;

        networkmanager)
            # 获取主网络连接
            if command -v nmcli &>/dev/null; then
                CONN=$(nmcli -g NAME con show --active | head -n 1)
                if [ -n "$CONN" ]; then
                    print_info "使用NetworkManager配置连接 '${BOLD}$CONN${NC}' 的DNS..."
                    nmcli con mod "$CONN" ipv4.dns "$PRIMARY_DNS $SECONDARY_DNS"
                    nmcli con up "$CONN"
                    print_success "已通过NetworkManager配置DNS"
                else
                    print_error "未找到活动的NetworkManager连接，尝试直接配置resolv.conf..."
                    direct_resolv_conf
                fi
            else
                print_warning "未找到nmcli命令，尝试直接配置resolv.conf..."
                direct_resolv_conf
            fi
            ;;

        traditional|*)
            print_info "使用传统方式配置DNS..."
            direct_resolv_conf
            ;;
    esac
}

# 修改systemd-resolved.conf文件
modify_resolved_conf() {
    # 备份配置文件
    if [ -f /etc/systemd/resolved.conf ]; then
        cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
        print_info "已备份原配置到 ${CYAN}/etc/systemd/resolved.conf.bak${NC}"
    fi

    # 修改systemd-resolved配置
    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=$PRIMARY_DNS $SECONDARY_DNS
FallbackDNS=
#Domains=
#LLMNR=no
#MulticastDNS=no
#DNSSEC=no
#DNSOverTLS=no
#Cache=yes
#DNSStubListener=yes
#ReadEtcHosts=yes
EOF

    # 重启systemd-resolved服务
    systemctl restart systemd-resolved
    print_success "已修改systemd-resolved配置文件并重启服务"
}

# 直接修改resolv.conf
direct_resolv_conf() {
    # 备份原始文件
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak
        print_info "已备份原配置到 ${CYAN}/etc/resolv.conf.bak${NC}"
    fi

    # 如果是符号链接，则删除
    if [ -L /etc/resolv.conf ]; then
        print_warning "检测到/etc/resolv.conf是符号链接，将创建静态文件..."
        rm /etc/resolv.conf
    fi

    # 创建新的resolv.conf
    cat > /etc/resolv.conf << EOF
# DNS配置由DNS配置优化工具生成 $(date)
nameserver $PRIMARY_DNS
EOF

    # 添加辅助DNS（如果存在）
    if [ -n "$SECONDARY_DNS" ]; then
        echo "nameserver $SECONDARY_DNS" >> /etc/resolv.conf
    fi

    # 添加额外选项
    echo "options edns0" >> /etc/resolv.conf

    print_success "已直接修改/etc/resolv.conf文件"
}

# 测试新配置
test_new_config() {
    print_header "测试新DNS配置"
    print_info "请稍候，给系统时间应用新配置..."
    sleep 2  # 给系统一点时间应用新配置

    TEST_DOMAINS=("www.google.com" "www.google-analytics.com" "youtube.com")

    for domain in "${TEST_DOMAINS[@]}"; do
        print_subheader "测试解析 ${BOLD}$domain${NC}:"
        if command -v dig &>/dev/null; then
            result=$(dig +short $domain)
            if [ -n "$result" ]; then
                print_success "成功解析: ${CYAN}$result${NC}"

                # 检查是否是北京IP
                if [[ "$result" == *"203.208"* ]]; then
                    print_warning "警告: 仍然解析到北京IP，可能影响访问速度"
                fi

                # 尝试反向解析
                reverse=$(dig +short -x $(echo "$result" | head -n1) 2>/dev/null)
                if [ -n "$reverse" ]; then
                    echo -e "  节点信息: ${BLUE}$reverse${NC}"
                fi
            else
                print_error "解析失败"
            fi
        elif command -v nslookup &>/dev/null; then
            nslookup $domain | grep -A2 "Name:"
        else
            ping -c 1 $domain &>/dev/null
            if [ $? -eq 0 ]; then
                print_success "成功ping通 $domain"
            else
                print_error "无法ping通 $domain"
            fi
        fi
        echo ""
    done
}

# 显示系统信息
show_system_info() {
    print_header "系统信息"
    echo -e "${BLUE}--------${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "操作系统: ${BOLD}$PRETTY_NAME${NC}"
    else
        echo -e "操作系统: ${BOLD}未知${NC}"
    fi

    echo -e "内核版本: ${BOLD}$(uname -r)${NC}"
    echo -e "主机名: ${BOLD}$(hostname)${NC}"
    echo ""
}

# 主程序流程
show_system_info
check_dns_system
test_dns_resolution
select_dns
apply_dns
test_new_config

echo -e "\n${BOLD}${GREEN}DNS配置优化完成！${NC}"
echo -e "${YELLOW}如果您需要恢复原始配置:${NC}"
echo -e "- 对于systemd-resolved: ${CYAN}systemctl restart systemd-resolved${NC}"
echo -e "- 对于传统配置: ${CYAN}cp /etc/resolv.conf.bak /etc/resolv.conf${NC}"
echo ""
echo -e "${BOLD}${BLUE}感谢使用DNS配置优化工具${NC}"
