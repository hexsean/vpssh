#!/bin/bash

# 日志函数
log() {
    echo -e "\n=== [$(date +'%Y-%m-%d %H:%M:%S')] $1 ==="
}

# 步骤日志
step_log() {
    echo -e "\n---> $1"
}

# 错误日志函数
error() {
    echo -e "\n!!! [$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1 !!!" >&2
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    error "请使用root权限运行此脚本"
    exit 1
fi

# 检查当前sshd配置
check_sshd_config() {
    log "检查SSH配置文件"
    
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        if ls /etc/ssh/sshd_config.d/*.conf >/dev/null 2>&1; then
            step_log "发现以下额外配置文件："
            for conf in /etc/ssh/sshd_config.d/*.conf; do
                echo -e "\n文件: $conf"
                cat "$conf"
            done
            
            read -p $'\n是否要删除这些配置文件？(y/n): ' choice
            if [ "$choice" = "y" ]; then
                step_log "删除额外配置文件..."
                rm -f /etc/ssh/sshd_config.d/*.conf
                step_log "已删除所有额外配置文件"
            fi
        else
            step_log "sshd_config.d 目录下没有发现额外配置文件"
        fi
    else
        step_log "创建 sshd_config.d 目录"
        mkdir -p /etc/ssh/sshd_config.d
    fi
}

# 配置SSH
configure_ssh() {
    log "配置SSH"
    
    # 创建新的配置文件
    CONFIG_FILE="/etc/ssh/sshd_config.d/port-settings.conf"
    
    step_log "创建新配置文件: $CONFIG_FILE"
    cat > "$CONFIG_FILE" << EOF
# Added by setup script $(date +'%Y-%m-%d %H:%M:%S')
Port 22088
PermitRootLogin yes
PasswordAuthentication yes
EOF
    
    step_log "确保主配置文件包含 .d 目录配置"
    if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    
    step_log "重启 SSH 服务"
    systemctl restart sshd
    
    if [ $? -eq 0 ]; then
        step_log "SSH 服务重启成功"
    else
        error "SSH 服务重启失败"
    fi
}

# 配置UFW
configure_ufw() {
    log "配置防火墙"
    
    if command -v ufw >/dev/null 2>&1; then
        step_log "UFW 已安装"
        
        # 检查UFW状态
        if ! ufw status | grep -q "Status: active"; then
            step_log "启用 UFW..."
            echo "y" | ufw enable
        fi
        
        step_log "配置 UFW 规则..."
        ufw allow 22088/tcp
        ufw delete allow 22/tcp
        
        step_log "当前 UFW 状态："
        ufw status
        
    else
        step_log "未发现 UFW"
        read -p $'\n是否安装并配置UFW？(y/n): ' choice
        if [ "$choice" = "y" ]; then
            step_log "安装 UFW..."
            apt update
            apt install -y ufw
            
            step_log "启用 UFW..."
            echo "y" | ufw enable
            
            step_log "配置 UFW 规则..."
            ufw allow 22088/tcp
            ufw delete allow 22/tcp
            
            step_log "当前 UFW 状态："
            ufw status
        else
            step_log "跳过 UFW 配置"
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
    step_log "请使用新端口 22088 确认是否可以正常连接"
    step_log "建议保持当前会话直到确认新配置正常工作"
}

# 运行主程序
main