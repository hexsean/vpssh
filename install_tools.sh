#!/bin/bash

# 确保脚本以root权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo "此脚本需要root权限，请使用sudo运行"
   exit 1
fi

echo "开始安装基本工具包..."

# 检测Linux发行版类型
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    echo "检测到Debian/Ubuntu系统"
    apt update
    apt install -y curl wget vim dnsutils
elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS/Fedora系统
    echo "检测到RHEL/CentOS/Fedora系统"
    dnf update -y || yum update -y
    dnf install -y curl wget vim bind-utils || yum install -y curl wget vim bind-utils
elif [ -f /etc/arch-release ]; then
    # Arch Linux系统
    echo "检测到Arch Linux系统"
    pacman -Sy
    pacman -S --noconfirm curl wget vim bind-tools
elif [ -f /etc/alpine-release ]; then
    # Alpine Linux系统
    echo "检测到Alpine Linux系统"
    apk update
    apk add curl wget vim bind-tools
else
    echo "无法识别的Linux发行版，请手动安装软件包"
    exit 1
fi

# 验证安装
echo "验证安装..."
TOOLS=("curl" "wget" "vim" "dig")
for tool in "${TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo "$tool 已成功安装"
    else
        echo "警告: $tool 可能未正确安装"
    fi
done

echo "安装完成！"
