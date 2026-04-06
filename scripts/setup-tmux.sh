#!/bin/bash
# @name: setup-tmux
# @description: 安装并配置 tmux（分屏、会话保活、鼠标支持、状态栏美化）
# @category: 环境配置
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

TMUX_CONF="${HOME}/.tmux.conf"

TMUX_CONF_CONTENT='# ---- 基础设置 ----

# 启用鼠标（点击切换面板、拖拽调整大小、滚轮翻页）
set -g mouse on

# 支持256色
set -g default-terminal "screen-256color"

# 窗口编号从1开始
set -g base-index 1
setw -g pane-base-index 1

# 关闭窗口后自动重新编号
set -g renumber-windows on

# ---- 状态栏 ----

# 刷新间隔（秒）
set -g status-interval 5

# 状态栏位置
set -g status-position bottom

# 整体配色：深灰底 + 浅色字
set -g status-style '\''bg=#1e1e2e fg=#cdd6f4'\''

# 左侧：会话名
set -g status-left-length 30
set -g status-left '\''#[bg=#89b4fa,fg=#1e1e2e,bold] #S #[default] '\''

# 右侧：日期时间
set -g status-right-length 50
set -g status-right '\''#[fg=#a6adc8] %m-%d %a %H:%M '\''

# 当前窗口样式（高亮）
setw -g window-status-current-format '\''#[bg=#cba6f7,fg=#1e1e2e,bold] #I:#W '\''

# 其他窗口样式
setw -g window-status-format '\''#[fg=#6c7086] #I:#W '\''

# ---- 面板边框 ----

set -g pane-border-style '\''fg=#313244'\''
set -g pane-active-border-style '\''fg=#89b4fa'\'''

# ---- 检测阶段 ----
detect_state() {
    PLAN=()

    if ! has_cmd tmux; then
        detect_distro
        PLAN+=("install_tmux|安装 tmux")
    fi

    if ! file_matches "${TMUX_CONF}" "${TMUX_CONF_CONTENT}"; then
        PLAN+=("write_conf|写入 .tmux.conf 配置（鼠标支持、状态栏美化）")
    fi
}

# ---- 展示计划 ----
show_plan() {
    print_header "tmux 环境配置计划"

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "tmux 环境已完全就绪，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_add "${desc}"
    done

    # 显示已就绪项
    if has_cmd tmux; then
        print_plan_skip "tmux 已安装 ($(tmux -V))"
    fi
    if file_matches "${TMUX_CONF}" "${TMUX_CONF_CONTENT}"; then
        print_plan_skip ".tmux.conf 内容一致"
    fi
}

# ---- 执行阶段 ----
execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            install_tmux)
                print_step "安装 tmux..."
                pkg_install tmux
                if has_cmd tmux; then
                    print_ok "tmux 安装完成 ($(tmux -V))"
                else
                    print_err "tmux 安装失败"
                    exit 1
                fi
                ;;
            write_conf)
                print_step "写入 .tmux.conf..."
                write_file_if_changed "${TMUX_CONF}" "${TMUX_CONF_CONTENT}"
                # 如果当前在 tmux 内，自动加载配置
                if [[ -n "${TMUX:-}" ]]; then
                    tmux source-file "${TMUX_CONF}" 2>/dev/null && print_ok "配置已热加载" || true
                fi
                ;;
        esac
    done

    print_header "完成"
    if [[ -z "${TMUX:-}" ]]; then
        echo -e "运行 ${BOLD}tmux new -s work${NC} 开始使用"
    fi
}

# ---- 主流程 ----
detect_state
show_plan
if confirm; then
    execute_plan
else
    echo "已取消操作"
fi
