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

# 改进参数提取方式
current_server=$(grep "ExecStart" "$SERVICE_FILE" | grep -o '"-s"[[:space:]]*"[^"]*"' | cut -d'"' -f4)
current_password=$(grep "ExecStart" "$SERVICE_FILE" | grep -o '"-p"[[:space:]]*"[^"]*"' | cut -d'"' -f4)

echo "检测到的服务器地址: $current_server"
echo "检测到的密码: $current_password"

if [ -z "$current_server" ] || [ -z "$current_password" ]; then
    echo "无法从现有配置中获取服务器地址或密码"
    exit 1
fi

# 创建新的配置，保持原有的其他设置
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=哪吒探针监控端
ConditionFileIsExecutable=/opt/nezha/agent/nezha-agent

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/nezha/agent/nezha-agent "-s" "${current_server}" "-p" "${current_password}" --disable-auto-update --disable-force-update --disable-command-execute --report-delay 3
WorkingDirectory=/root
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/nezha-agent

[Install]
WantedBy=multi-user.target
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
