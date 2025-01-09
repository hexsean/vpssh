#!/bin/bash

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 错误日志函数
error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    error "请使用root权限运行此脚本"
    exit 1
fi

# 备份sshd配置
backup_sshd_config() {
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
    log "已备份SSH配置文件"
}

# 检查当前sshd配置
check_sshd_config() {
    log "检查当前SSH配置..."
    if grep -v '^#' /etc/ssh/sshd_config | grep -v '^$'; then
        log "发现以下非注释配置："
        grep -v '^#' /etc/ssh/sshd_config | grep -v '^$'
        
        read -p "是否要删除现有配置？(y/n): " choice
        if [ "$choice" = "y" ]; then
            backup_sshd_config
            # 清除所有非默认配置（保留注释）
            sed -i '/^[^#]/d' /etc/ssh/sshd_config
            log "已清除现有配置"
        fi
    else
        log "未发现额外配置"
    fi
}

# 配置SSH
configure_ssh() {
    log "配置SSH..."
    backup_sshd_config
    
    # 添加新配置
    cat >> /etc/ssh/sshd_config << EOF

# Added by setup script
Port 22088
PasswordAuthentication yes
EOF
    
    log "SSH配置已更新"
    systemctl restart sshd
    log "SSH服务已重启"
}

# 配置UFW
configure_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        log "发现UFW已安装"
        
        # 检查UFW状态
        if ! ufw status | grep -q "Status: active"; then
            log "启用UFW..."
            echo "y" | ufw enable
        fi
        
        log "配置UFW规则..."
        ufw allow 22088/tcp
        ufw delete allow 22/tcp
        log "UFW规则已更新"
        
    else
        log "未发现UFW"
        read -p "是否安装并配置UFW？(y/n): " choice
        if [ "$choice" = "y" ]; then
            apt update
            apt install -y ufw
            log "UFW已安装"
            
            log "启用UFW..."
            echo "y" | ufw enable
            
            log "配置UFW规则..."
            ufw allow 22088/tcp
            ufw delete allow 22/tcp
            log "UFW规则已更新"
        else
            log "跳过UFW配置"
        fi
    fi
}

# 主程序
main() {
    log "开始配置..."
    
    check_sshd_config
    configure_ssh
    configure_ufw
    
    log "配置完成"
    log "请使用新端口 22088 确认是否可以正常连接"
    log "建议保持当前会话直到确认新配置正常工作"
}

# 运行主程序
main