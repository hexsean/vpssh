#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要root权限运行"
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 检查nezha-agent是否安装
if ! systemctl list-unit-files | grep -q nezha-agent; then
    echo "未检测到nezha-agent服务"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/nezha-agent.service"

# 检查服务文件是否存在
if [ ! -f "$SERVICE_FILE" ]; then
    echo "未找到nezha-agent服务配置文件"
    exit 1
fi

# 备份原配置文件
cp "$SERVICE_FILE" "${SERVICE_FILE}.backup.$(date +%Y%m%d%H%M%S)"

# 获取当前的服务器地址和密码
current_server=$(grep "ExecStart" "$SERVICE_FILE" | grep -o '\-s [^ ]*' | cut -d' ' -f2)
current_password=$(grep "ExecStart" "$SERVICE_FILE" | grep -o '\-p [^ ]*' | cut -d' ' -f2)

if [ -z "$current_server" ] || [ -z "$current_password" ]; then
    echo "无法从现有配置中获取服务器地址或密码"
    exit 1
fi

# 创建新的配置
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=哪吒探针监控端
ConditionFileIsExecutable=/opt/nezha/agent/nezha-agent

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/nezha/agent/nezha-agent "-s" ${current_server} "-p" ${current_password} --disable-auto-update --disable-force-update --disable-command-execute

WorkingDirectory=/root

Restart=always

RestartSec=120
EnvironmentFile=-/etc/sysconfig/nezha-agent


EOF

echo "配置文件已更新"

# 重启服务
echo "重新加载systemd配置..."
systemctl daemon-reload

echo "重启nezha-agent服务..."
systemctl restart nezha-agent

# 检查服务状态
echo "检查服务状态..."
sleep 2
systemctl status nezha-agent

echo "完成！"
