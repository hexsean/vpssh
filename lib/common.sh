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

# ---- 托管块工具 ----
# 在文件中管理 BEGIN/END 标记包裹的区域，不影响用户手写的其他内容

MANAGED_BEGIN="# ---- BEGIN vpssh managed ----"
MANAGED_END="# ---- END vpssh managed ----"

has_managed_block_pair() {
    local file="$1"
    [[ -f "${file}" ]] || return 1
    grep -qFx "${MANAGED_BEGIN}" "${file}" && grep -qFx "${MANAGED_END}" "${file}"
}

has_partial_managed_block() {
    local file="$1"
    [[ -f "${file}" ]] || return 1

    local has_begin=1
    local has_end=1

    grep -qFx "${MANAGED_BEGIN}" "${file}" && has_begin=0
    grep -qFx "${MANAGED_END}" "${file}" && has_end=0

    [[ "${has_begin}" -ne "${has_end}" ]]
}

managed_block_matches() {
    local file="$1"
    local content="$2"

    has_managed_block_pair "${file}" || return 1

    local current
    current="$(awk -v begin="${MANAGED_BEGIN}" -v end="${MANAGED_END}" '
        $0 == begin { in_block=1 }
        in_block { print }
        in_block && $0 == end { exit }
    ' "${file}" 2>/dev/null)"
    local expected
    expected="$(printf '%s\n%s\n%s' "${MANAGED_BEGIN}" "${content}" "${MANAGED_END}")"
    [[ "${current}" == "${expected}" ]]
}

write_managed_block() {
    local file="$1"
    local content="$2"
    local block
    block="$(printf '%s\n%s\n%s' "${MANAGED_BEGIN}" "${content}" "${MANAGED_END}")"

    if [[ ! -f "${file}" ]]; then
        mkdir -p "$(dirname "${file}")"
        echo "${block}" > "${file}"
        print_ok "已创建: ${file}"
    elif has_managed_block_pair "${file}"; then
        # 替换已有的托管块
        local tmp="${file}.vpssh.tmp"
        awk -v begin="${MANAGED_BEGIN}" -v end="${MANAGED_END}" -v block="${block}" '
            $0 == begin { print block; skip=1; next }
            skip && $0 == end { skip=0; next }
            !skip { print }
        ' "${file}" > "${tmp}"
        mv "${tmp}" "${file}"
        print_ok "已更新托管块: ${file}"
    elif has_partial_managed_block "${file}"; then
        print_err "检测到不完整的托管块，拒绝自动修改: ${file}"
        return 1
    else
        # 文件存在但没有托管块，追加到末尾，尽量不改变用户现有加载顺序
        local tmp="${file}.vpssh.tmp"
        cat "${file}" > "${tmp}"
        if [[ -s "${file}" ]]; then
            if [[ -n "$(tail -c 1 "${file}" 2>/dev/null)" ]]; then
                printf '\n' >> "${tmp}"
            fi
            printf '\n' >> "${tmp}"
        fi
        printf '%s\n' "${block}" >> "${tmp}"
        mv "${tmp}" "${file}"
        print_ok "已追加托管块: ${file}"
    fi
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
