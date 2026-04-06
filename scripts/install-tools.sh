#!/bin/bash
# @name: install-tools
# @description: 安装基础工具包（curl、wget、vim、dig、sudo）
# @category: 环境配置
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

# 工具名到包名的映射
pkg_name_for() {
    local tool="$1"
    case "${DISTRO}" in
        debian)
            case "${tool}" in
                dig) echo "dnsutils" ;;
                *) echo "${tool}" ;;
            esac
            ;;
        redhat)
            case "${tool}" in
                dig) echo "bind-utils" ;;
                *) echo "${tool}" ;;
            esac
            ;;
        arch|alpine)
            case "${tool}" in
                dig) echo "bind-tools" ;;
                *) echo "${tool}" ;;
            esac
            ;;
    esac
}

TOOLS=("curl" "wget" "vim" "dig" "sudo" "git")

# ---- 检测阶段 ----
detect_state() {
    PLAN=()
    PACKAGES_TO_INSTALL=()

    detect_distro

    for tool in "${TOOLS[@]}"; do
        if has_cmd "${tool}"; then
            continue
        fi
        local pkg
        pkg="$(pkg_name_for "${tool}")"
        PACKAGES_TO_INSTALL+=("${pkg}")
        PLAN+=("install|安装 ${tool} (包: ${pkg})")
    done
}

# ---- 展示计划 ----
show_plan() {
    print_header "基础工具安装计划"
    echo -e "  发行版: ${BOLD}${DISTRO}${NC}"
    echo ""

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "所有工具已安装，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_add "${desc}"
    done

    for tool in "${TOOLS[@]}"; do
        if has_cmd "${tool}"; then
            print_plan_skip "${tool} 已安装"
        fi
    done
}

# ---- 执行阶段 ----
execute_plan() {
    if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
        return
    fi

    print_step "安装: ${PACKAGES_TO_INSTALL[*]}"
    pkg_install "${PACKAGES_TO_INSTALL[@]}"

    # 验证
    print_header "验证安装"
    for tool in "${TOOLS[@]}"; do
        if has_cmd "${tool}"; then
            print_ok "${tool}"
        else
            print_err "${tool} 安装失败"
        fi
    done
}

# ---- 主流程 ----
detect_state
show_plan
if confirm; then
    execute_plan
    print_header "安装完成"
else
    echo "已取消操作"
fi
