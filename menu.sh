#!/bin/bash
# @name: menu
# @description: VPS 工具集统一入口菜单（支持 curl | bash 远程执行）
# @category: 入口
# @requires: none
# @idempotent: true

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/hexsean/vpssh/main"

# ---- 内联颜色（自包含，与 lib/common.sh 保持同步） ----
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ---- 脚本注册表 ----
# 格式: "文件名|分类|描述|需要root"
REGISTRY=(
    "install-tools.sh|环境配置|安装基础工具包（curl、wget、vim、dig、sudo）|root"
    "setup-zsh.sh|环境配置|一键配置 zsh 环境（插件、补全、提示符、别名）|root"
    "setup-ssh.sh|安全|SSH 密钥认证加固（禁用密码登录、更改端口、配置 UFW 防火墙）|root"
    "configure-dns.sh|网络|DNS 解析检测与优化（测试多 DNS 服务器，可切换配置）|root"
    "configure-nezha.sh|监控|哪吒探针安全加固（禁用自动更新、远程命令执行）|root"
    "check-docker-logs.sh|运维|检查 Docker 日志配置及磁盘空间占用情况|root"
)

# ---- 显示菜单 ----
show_menu() {
    echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║          VPS 工具集  v1.0                ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    local last_category=""
    local index=1

    for entry in "${REGISTRY[@]}"; do
        local file category desc requires
        IFS='|' read -r file category desc requires <<< "${entry}"

        if [[ "${category}" != "${last_category}" ]]; then
            echo -e "\n  ${BOLD}${YELLOW}[ ${category} ]${NC}"
            last_category="${category}"
        fi

        local root_tag=""
        if [[ "${requires}" == "root" ]]; then
            root_tag="${DIM}(root)${NC}"
        fi

        echo -e "    ${BOLD}${index})${NC} ${desc} ${root_tag}"
        index=$((index + 1))
    done

    echo -e "\n    ${BOLD}0)${NC} 退出"
    echo ""
}

# ---- 下载并执行脚本 ----
run_script() {
    local script_file="$1"
    trap 'rm -f /tmp/vpssh-common.sh "/tmp/vpssh-${script_file}"' RETURN

    echo -e "\n${CYAN}---> 下载脚本...${NC}"
    curl -fsSL "${REPO_RAW}/lib/common.sh" -o /tmp/vpssh-common.sh &
    curl -fsSL "${REPO_RAW}/scripts/${script_file}" -o "/tmp/vpssh-${script_file}" &
    wait

    if [[ ! -s /tmp/vpssh-common.sh ]] || [[ ! -s "/tmp/vpssh-${script_file}" ]]; then
        echo -e "${RED}下载失败${NC}"
        return 1
    fi

    echo -e "${CYAN}---> 执行 ${script_file} ...${NC}\n"
    bash "/tmp/vpssh-${script_file}"
}

# ---- 主循环 ----
main() {
    while true; do
        show_menu
        read -r -p "$(echo -e "${BOLD}${CYAN}请选择功能 [0-${#REGISTRY[@]}]: ${NC}")" choice </dev/tty

        if [[ "${choice}" == "0" ]]; then
            echo -e "${GREEN}再见！${NC}"
            exit 0
        fi

        if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le ${#REGISTRY[@]} ]]; then
            local entry="${REGISTRY[$((choice - 1))]}"
            local file
            IFS='|' read -r file _ _ _ <<< "${entry}"
            run_script "${file}"

            echo ""
            read -r -p "$(echo -e "${DIM}按回车返回菜单...${NC}")" _ </dev/tty
        else
            echo -e "${RED}无效选项${NC}"
        fi
    done
}

main
