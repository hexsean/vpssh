#!/bin/bash
# @name: common
# @description: 公共颜色、打印、确认、幂等工具函数
# @category: 库
# @requires: none

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

# 检查命令是否存在
has_cmd() {
    command -v "$1" &>/dev/null
}

# 检查 apt 包是否已安装
is_pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# 检查文件内容是否匹配（幂等写入）
file_matches() {
    local file="$1"
    local content="$2"
    [[ -f "${file}" ]] && [[ "$(cat "${file}")" == "${content}" ]]
}

# 安全写入文件（仅在内容不同时写入）
write_file_if_changed() {
    local file="$1"
    local content="$2"
    if file_matches "${file}" "${content}"; then
        print_skip "文件无变化: ${file}"
        return 1
    fi
    mkdir -p "$(dirname "${file}")"
    echo "${content}" > "${file}"
    print_ok "已写入: ${file}"
    return 0
}

# 确保以 root 运行
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_err "此脚本需要 root 权限，请使用 sudo 运行"
        exit 1
    fi
}

# 显示脚本元信息
show_meta() {
    local script="$1"
    local name description category
    name=$(grep '^# @name:' "${script}" | head -1 | sed 's/^# @name: *//')
    description=$(grep '^# @description:' "${script}" | head -1 | sed 's/^# @description: *//')
    category=$(grep '^# @category:' "${script}" | head -1 | sed 's/^# @category: *//')
    echo -e "${BOLD}${name}${NC} - ${description} [${category}]"
}
