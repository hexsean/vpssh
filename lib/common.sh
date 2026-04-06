#!/bin/bash
# @name: common
# @description: 公共颜色、打印、确认、幂等工具函数
# @category: 库
# @requires: none
# @idempotent: true

# NOTE: 颜色常量在 menu.sh 中有副本（menu.sh 需自包含以支持 curl|bash）
# ---- 颜色 ----
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ---- 打印函数 ----
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
}

print_step() {
    echo -e "${CYAN}---> $1${NC}"
}

print_ok() {
    echo -e "${GREEN}  [OK] $1${NC}"
}

print_skip() {
    echo -e "${DIM}  [已就绪] $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  [注意] $1${NC}"
}

print_err() {
    echo -e "${RED}  [错误] $1${NC}" >&2
}

print_plan_add() {
    echo -e "${GREEN}  [+] $1${NC}"
}

print_plan_change() {
    echo -e "${YELLOW}  [~] $1${NC}"
}

print_plan_skip() {
    echo -e "${DIM}  [-] $1 (已就绪，跳过)${NC}"
}

# ---- 确认函数 ----
confirm() {
    local prompt="${1:-确认执行以上操作？}"
    echo ""
    read -r -p "$(echo -e "${BOLD}${YELLOW}${prompt} [y/N]: ${NC}")" answer </dev/tty
    [[ "${answer}" =~ ^[Yy]$ ]]
}

# ---- 幂等工具 ----

has_cmd() {
    command -v "$1" &>/dev/null
}

file_matches() {
    local file="$1"
    local content="$2"
    [[ -f "${file}" ]] && [[ "$(cat "${file}")" == "${content}" ]]
}

write_file_if_changed() {
    local file="$1"
    local content="$2"
    if file_matches "${file}" "${content}"; then
        print_skip "文件无变化: ${file}"
        return 0
    fi
    mkdir -p "$(dirname "${file}")"
    echo "${content}" > "${file}"
    print_ok "已写入: ${file}"
    return 0
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_err "此脚本需要 root 权限，请使用 sudo 运行"
        exit 1
    fi
}

# ---- 发行版检测 ----

detect_distro() {
    if [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="redhat"
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
    elif [[ -f /etc/alpine-release ]]; then
        DISTRO="alpine"
    else
        print_err "无法识别的 Linux 发行版"
        exit 1
    fi
}

pkg_install() {
    case "${DISTRO}" in
        debian)  apt update -y && apt install -y "$@" ;;
        redhat)  dnf install -y "$@" 2>/dev/null || yum install -y "$@" ;;
        arch)    pacman -Sy --noconfirm "$@" ;;
        alpine)  apk update && apk add "$@" ;;
    esac
}
