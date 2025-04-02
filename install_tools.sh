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

print_command() {
    echo -e "${CYAN}$1${NC}"
}

# 确保脚本以root权限运行
if [ "$(id -u)" -ne 0 ]; then
   print_error "此脚本需要root权限，请使用sudo运行"
   exit 1
fi

# 标题
echo -e "\n${BOLD}${BLUE}=================================${NC}"
echo -e "${BOLD}${BLUE}      Linux基本工具安装脚本      ${NC}"
echo -e "${BOLD}${BLUE}=================================${NC}"

print_header "开始安装基本工具包"

# 检测Linux发行版类型
print_subheader "检测系统类型..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    print_info "检测到 ${BOLD}Debian/Ubuntu${NC} 系统"
    print_command "apt update"
    apt update
    print_command "apt install -y curl wget vim dnsutils"
    apt install -y curl wget vim dnsutils
elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS/Fedora系统
    print_info "检测到 ${BOLD}RHEL/CentOS/Fedora${NC} 系统"
    print_command "dnf update -y || yum update -y"
    dnf update -y || yum update -y
    print_command "dnf install -y curl wget vim bind-utils || yum install -y curl wget vim bind-utils"
    dnf install -y curl wget vim bind-utils || yum install -y curl wget vim bind-utils
elif [ -f /etc/arch-release ]; then
    # Arch Linux系统
    print_info "检测到 ${BOLD}Arch Linux${NC} 系统"
    print_command "pacman -Sy"
    pacman -Sy
    print_command "pacman -S --noconfirm curl wget vim bind-tools"
    pacman -S --noconfirm curl wget vim bind-tools
elif [ -f /etc/alpine-release ]; then
    # Alpine Linux系统
    print_info "检测到 ${BOLD}Alpine Linux${NC} 系统"
    print_command "apk update"
    apk update
    print_command "apk add curl wget vim bind-tools"
    apk add curl wget vim bind-tools
else
    print_error "无法识别的Linux发行版，请手动安装软件包"
    exit 1
fi

# 验证安装
print_header "验证安装"
TOOLS=("curl" "wget" "vim" "dig" "sudo")
for tool in "${TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        print_success "$tool 已成功安装"
    else
        print_warning "$tool 可能未正确安装"
    fi
done

echo -e "\n${BOLD}${GREEN}安装完成！${NC}"
echo -e "${BLUE}--------------------${NC}"
echo -e "${CYAN}已安装的工具可直接在命令行中使用${NC}"
