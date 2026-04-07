#!/bin/bash
# @name: setup-zsh
# @description: 一键配置 zsh 环境（插件、补全、提示符、别名）
# @category: 环境配置
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

# 确定目标用户：通过 sudo 执行时使用原始用户，直接 root 执行时使用 root
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

ZSH_PLUGIN_DIR="${TARGET_HOME}/.zsh/plugins"
ZSHRC="${TARGET_HOME}/.zshrc"

PLUGINS=(
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
    "zsh-z|https://github.com/agkozak/zsh-z"
)

ZSHRC_CONTENT='# ---- PATH（继承 ~/.profile 中的环境变量，如 nvm、npm、cargo 等） ----
[[ -f ~/.profile ]] && emulate sh -c '\''source ~/.profile'\''

# ---- History ----
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# ---- Completion ----
autoload -Uz compinit && compinit
zstyle '\'':completion:*'\'' menu select
zstyle '\'':completion:*'\'' matcher-list '\''m:{a-z}={A-Z}'\''

# ---- Plugins ----
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/plugins/zsh-z/zsh-z.plugin.zsh

# ---- Prompt ----
PROMPT='\''%F{cyan}%n@%m%f:%F{green}%~%f %# '\''

# ---- Aliases ----
alias ll='\''ls -alF'\''
alias la='\''ls -A'\'''

# ---- 检测阶段 ----
detect_state() {
    PLAN=()

    if ! has_cmd zsh; then
        PLAN+=("install_zsh|安装 zsh 和 git")
    fi

    if ! has_cmd zsh || [[ "$(getent passwd "${TARGET_USER}" | cut -d: -f7)" != "$(which zsh 2>/dev/null)" ]]; then
        PLAN+=("set_default_shell|设置 zsh 为 ${TARGET_USER} 的默认 shell")
    fi

    for entry in "${PLUGINS[@]}"; do
        local name="${entry%%|*}"
        local url="${entry##*|}"
        if [[ ! -d "${ZSH_PLUGIN_DIR}/${name}" ]]; then
            PLAN+=("clone_plugin|安装插件: ${name}|${name}|${url}")
        fi
    done

    if ! file_matches "${ZSHRC}" "${ZSHRC_CONTENT}"; then
        PLAN+=("write_zshrc|写入 .zshrc 配置")
    fi
}

# ---- 展示计划 ----
show_plan() {
    print_header "zsh 环境配置计划"

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "zsh 环境已完全就绪，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_add "${desc}"
    done

    # 显示已就绪项
    if has_cmd zsh; then
        print_plan_skip "zsh 已安装"
    fi
    for entry in "${PLUGINS[@]}"; do
        local name="${entry%%|*}"
        if [[ -d "${ZSH_PLUGIN_DIR}/${name}" ]]; then
            print_plan_skip "插件 ${name}"
        fi
    done
    if file_matches "${ZSHRC}" "${ZSHRC_CONTENT}"; then
        print_plan_skip ".zshrc 内容一致"
    fi
}

# ---- 执行阶段 ----
execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            install_zsh)
                print_step "更新 apt 并安装 zsh、git..."
                apt update -y && apt install -y zsh git
                print_ok "zsh 和 git 安装完成"
                ;;
            set_default_shell)
                print_step "设置 zsh 为 ${TARGET_USER} 的默认 shell..."
                chsh -s "$(which zsh)" "${TARGET_USER}"
                print_ok "${TARGET_USER} 的默认 shell 已设为 zsh"
                ;;
            clone_plugin)
                local name url
                name="$(echo "${item}" | cut -d'|' -f3)"
                url="$(echo "${item}" | cut -d'|' -f4)"
                print_step "克隆插件 ${name}..."
                mkdir -p "${ZSH_PLUGIN_DIR}"
                chown "${TARGET_USER}":"${TARGET_USER}" "${TARGET_HOME}/.zsh" "${ZSH_PLUGIN_DIR}"
                git clone --depth=1 "${url}" "${ZSH_PLUGIN_DIR}/${name}"
                chown -R "${TARGET_USER}":"${TARGET_USER}" "${ZSH_PLUGIN_DIR}/${name}"
                print_ok "插件 ${name} 安装完成"
                ;;
            write_zshrc)
                print_step "写入 .zshrc..."
                write_file_if_changed "${ZSHRC}" "${ZSHRC_CONTENT}"
                chown "${TARGET_USER}":"${TARGET_USER}" "${ZSHRC}"
                ;;
        esac
    done

    print_header "完成"
    echo -e "请运行 ${BOLD}exec zsh${NC} 或重新登录以生效"
}

# ---- 主流程 ----
detect_state
show_plan
if confirm; then
    execute_plan
else
    echo "已取消操作"
fi
