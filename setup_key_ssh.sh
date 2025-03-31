#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "\n${BOLD}${BLUE}=== [$(date +'%Y-%m-%d %H:%M:%S')] $1 ===${NC}"
}

# 步骤日志
step_log() {
    echo -e "\n${CYAN}---> $1${NC}"
}

# 错误日志函数
error() {
    echo -e "\n${BOLD}${RED}!!! [$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1 !!!${NC}" >&2
}

# 成功日志
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 警告日志
warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# 信息日志
info() {
    echo -e "${BLUE}$1${NC}"
}

# 显示文件内容
show_file() {
    echo -e "${YELLOW}文件: $1${NC}"
    echo -e "${MAGENTA}$(cat "$1")${NC}"
}

# 显示命令提示
cmd() {
    echo -e "${BOLD}${MAGENTA}$ $1${NC}"
}

# 获取用户输入
get_input() {
    echo -e "${BOLD}${YELLOW}$1${NC}"
    if [ -t 0 ]; then
        # 有TTY，读取输入
        read choice </dev/tty
    else
        # 无TTY，使用默认值
        choice="n"
        echo "自动选择: $choice (非交互模式)"
    fi
    echo "$choice"
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    error "请使用root权限运行此脚本"
    echo -e "${CYAN}提示: 使用 ${BOLD}sudo bash $0${NC} ${CYAN}重新运行${NC}"
    exit 1
fi

# 显示标题
echo -e "\n${BOLD}${BLUE}=================================${NC}"
echo -e "${BOLD}${BLUE}      SSH安全配置工具      ${NC}"
echo -e "${BOLD}${BLUE}=================================${NC}"

# 检查当前sshd配置
check_sshd_config() {
    log "检查SSH配置文件"

    if [ -d "/etc/ssh/sshd_config.d" ]; then
        if ls /etc/ssh/sshd_config.d/*.conf >/dev/null 2>&1; then
            step_log "发现以下额外配置文件："
            for conf in /etc/ssh/sshd_config.d/*.conf; do
                echo -e "\n${YELLOW}文件: $conf${NC}"
                echo -e "${MAGENTA}$(cat "$conf")${NC}"
            done

            choice=$(get_input $'\n是否要删除这些配置文件？(y/n): ')
            if [ "$choice" = "y" ]; then
                step_log "删除额外配置文件..."
                cmd "rm -f /etc/ssh/sshd_config.d/*.conf"
                rm -f /etc/ssh/sshd_config.d/*.conf
                success "已删除所有额外配置文件"
            fi
        else
            info "sshd_config.d 目录下没有发现额外配置文件"
        fi
    else
        step_log "创建 sshd_config.d 目录"
        cmd "mkdir -p /etc/ssh/sshd_config.d"
        mkdir -p /etc/ssh/sshd_config.d
        success "目录创建完成"
    fi
}

# 配置SSH
configure_ssh() {
    log "配置SSH"

    # 创建新的配置文件
    CONFIG_FILE="/etc/ssh/sshd_config.d/port-settings.conf"
    step_log "创建新配置文件: ${BOLD}$CONFIG_FILE${NC}"

    # 创建authorized_keys文件
    step_log "配置SSH密钥认证"
    cmd "mkdir -p /root/.ssh"
    mkdir -p /root/.ssh

    cmd "chmod 700 /root/.ssh"
    chmod 700 /root/.ssh

    cmd "touch /root/.ssh/authorized_keys"
    touch /root/.ssh/authorized_keys

    cmd "chmod 600 /root/.ssh/authorized_keys"
    chmod 600 /root/.ssh/authorized_keys

    info "添加SSH公钥到 authorized_keys"
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDC7iifpQgGRzdKQqYOhp6EsNk/UL/O/Yjuarz/YqKKbz1Mnn+CKRBsyYtDJbmrcmteh6VwINHOQrK5sxy7rilIcQLQFBBg2uRA9Fhy9auqkTHXDvSyBhuwr93kcXvrpQFR3FVZlJfMb4c06sTVgOeWjcxqTnxnu/KkwFubWCgxulJ+62bNQeXZlRPJZTS+jMZV1Tro2i1+Ki9xsbgaFjnZpO+MKGt2Cy8/53gAAcbn9jvA2jysT5mqly3G8t4leeRKZprLMZMXmKV4uauD9L4o/jGQ1AZQgK20FP7A0QtYSqzGrnnCYMqvQXfVDWYWCFDBYya2uz2vjlzWdEyvOWaidSR7DMp+1p14CFe8qHtITmBr0zVrk+4Mn1xBO7byHRP47RzVcVglmsX4Mi8knqfOh16YwcyqUrUztRv5JUZlkDj3VSmnlJcx01b/otgQlTDfqV/407pv7KjrNGXQTQPGdk0OFDGDPrJVkm7isVx88SG0Nc3NCV92uNHWGhdqxNMgL6vl2bdXc7r13pTo/aGMMUCrK8zIKBpnbOqI2jUgBDZOF9Xky8X7nMIuQgXwNx0VhP9+K4kfhGWMalWf9ZWhRKGNtgrWbKGECxJi4HUQqePr0r8V8nSuZlGJ0+KjmwVkWrDtSJMvlGuIW+OAdegrvrK7ujvaIwt/iZW7JFNWXw== 12868@AllCanPC
" > /root/.ssh/authorized_keys
    success "SSH公钥已添加"

    step_log "创建SSH配置文件"
    info "写入以下内容到 ${BOLD}$CONFIG_FILE${NC}:"
    echo -e "${MAGENTA}# Added by setup script $(date +'%Y-%m-%d %H:%M:%S')
Port 22088
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys${NC}"

    cat > "$CONFIG_FILE" << EOF
# Added by setup script $(date +'%Y-%m-%d %H:%M:%S')
Port 22088
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys
EOF
    success "配置文件已创建"

    step_log "确保主配置文件包含 .d 目录配置"
    if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
        cmd "echo \"Include /etc/ssh/sshd_config.d/*.conf\" >> /etc/ssh/sshd_config"
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        success "已添加包含语句到主配置文件"
    else
        success "主配置文件已包含 .d 目录配置"
    fi

    step_log "重启 SSH 服务"
    cmd "systemctl restart sshd"
    systemctl restart sshd

    if [ $? -eq 0 ]; then
        success "SSH 服务重启成功"
    else
        error "SSH 服务重启失败"
    fi
}

# 配置UFW
configure_ufw() {
    log "配置防火墙"

    if command -v ufw >/dev/null 2>&1; then
        success "UFW 已安装"

        # 检查UFW状态
        if ! ufw status | grep -q "Status: active"; then
            step_log "启用 UFW..."
            warning "此操作可能临时断开网络连接"
            cmd "echo \"y\" | ufw enable"
            echo "y" | ufw enable
            success "UFW 已启用"
        else
            info "UFW 已处于启用状态"
        fi

        step_log "配置 UFW 规则..."
        cmd "ufw allow 22088/tcp"
        ufw allow 22088/tcp
        success "已允许 SSH 新端口 22088"

        cmd "ufw delete allow 22/tcp"
        ufw delete allow 22/tcp
        success "已删除默认 SSH 端口 22 规则"

        step_log "当前 UFW 状态："
        cmd "ufw status"
        echo -e "${CYAN}$(ufw status)${NC}"

    else
        warning "未发现 UFW"
        choice=$(get_input $'\n是否安装并配置UFW？(y/n): ')
        if [ "$choice" = "y" ]; then
            step_log "安装 UFW..."
            cmd "apt update"
            apt update

            cmd "apt install -y ufw"
            apt install -y ufw
            success "UFW 安装完成"

            step_log "启用 UFW..."
            warning "此操作可能临时断开网络连接"
            cmd "echo \"y\" | ufw enable"
            echo "y" | ufw enable
            success "UFW 已启用"

            step_log "配置 UFW 规则..."
            cmd "ufw allow 22088/tcp"
            ufw allow 22088/tcp
            success "已允许 SSH 新端口 22088"

            cmd "ufw delete allow 22/tcp"
            ufw delete allow 22/tcp
            success "已删除默认 SSH 端口 22 规则"

            step_log "当前 UFW 状态："
            cmd "ufw status"
            echo -e "${CYAN}$(ufw status)${NC}"
        else
            info "跳过 UFW 配置"
        fi
    fi
}

# 主程序
main() {
    log "开始配置"

    check_sshd_config
    configure_ssh
    configure_ufw

    log "配置完成"
    echo -e "\n${BOLD}${GREEN}=== 重要提示 ===${NC}"
    warning "请使用新端口 ${BOLD}22088${NC} 确认是否可以正常连接"
    warning "建议保持当前会话直到确认新配置正常工作"
    echo -e "\n${BOLD}${GREEN}=== 安全提示 ===${NC}"
    info "已配置以下安全措施:"
    echo -e "  ${GREEN}✓${NC} SSH端口已更改为非默认值 (${BOLD}22088${NC})"
    echo -e "  ${GREEN}✓${NC} 已禁用密码登录，仅允许密钥认证"
    echo -e "  ${GREEN}✓${NC} 已配置UFW防火墙仅允许新SSH端口"
}

# 运行主程序
main
