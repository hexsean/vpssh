# VPS 脚本工具集重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将零散的 VPS 管理脚本重构为统一风格、幂等、透明确认的工具集，并提供 `curl | bash` 一键入口菜单。

**Architecture:** 公共函数抽取到 `lib/common.sh`，每个脚本遵循"检测 → 展示计划 → 确认 → 执行"模式。入口 `menu.sh` 内嵌注册表，按分类展示菜单，选中后从 GitHub raw URL 下载执行。

**Tech Stack:** Bash 5+, GitHub Raw CDN

**Raw Base URL:** `https://raw.githubusercontent.com/hexsean/vpssh/main`

---

## 文件结构

```
vpssh/
├── menu.sh                      # 入口菜单脚本
├── lib/
│   └── common.sh                # 公共颜色、打印、确认、幂等工具函数
├── scripts/
│   ├── setup-zsh.sh             # zsh 环境一键配置
│   ├── setup-ssh.sh             # SSH 密钥加固（合并原两个脚本）
│   ├── configure-dns.sh         # DNS 检测与优化
│   ├── check-docker-logs.sh     # Docker 日志空间检查
│   ├── configure-nezha.sh       # 哪吒探针安全加固
│   └── install-tools.sh         # 基础工具安装
├── docs/
│   └── superpowers/
│       └── plans/
│           └── 2026-04-05-script-refactor.md
└── README.md
```

**删除旧文件：** `setup_key_ssh.sh`, `setup_ssh.sh`, `nezha.sh`, `docker_logs_check.sh`, `install_tools.sh`, `configure_dns.sh`, `setup-zsh.sh`

---

## 统一设计规范

### 元数据格式（每个脚本头部）

```bash
#!/bin/bash
# @name: <kebab-case-name>
# @description: <一句话描述功能>
# @category: <分类：环境配置 | 安全 | 网络 | 监控 | 运维>
# @requires: <root | none>
# @idempotent: true
```

### 统一执行模式："确认策略，最后执行"

每个脚本遵循以下流程：

```
detect_state()     → 检测当前系统状态
build_plan()       → 对比目标状态，生成变更列表
show_plan()        → 展示"将要做什么"（绿色=新增，黄色=变更，灰色=已就绪跳过）
confirm()          → 用户确认 (y/n)
execute_plan()     → 逐步执行，每步输出结果
```

### 幂等保证

- 每个操作前检查当前状态，已就绪则跳过并标记 `[已就绪]`
- 文件写入前比较内容，相同则跳过
- 包安装前检查是否已安装
- 服务配置前检查当前值

---

## Task 1: 创建 lib/common.sh 公共库

**Files:**
- Create: `lib/common.sh`

- [ ] **Step 1: 创建 lib/common.sh**

```bash
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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n lib/common.sh`
Expected: 无输出（无语法错误）

- [ ] **Step 3: Commit**

```bash
git add lib/common.sh
git commit -m "feat: add shared common.sh library for colors, printing, and idempotent helpers"
```

---

## Task 2: 重写 scripts/setup-zsh.sh

**Files:**
- Create: `scripts/setup-zsh.sh`
- Delete: `setup-zsh.sh` (旧文件，最终统一删除)

- [ ] **Step 1: 创建 scripts/setup-zsh.sh**

```bash
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

ZSH_PLUGIN_DIR="${HOME}/.zsh/plugins"
ZSHRC="${HOME}/.zshrc"

PLUGINS=(
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
    "zsh-z|https://github.com/agkozak/zsh-z"
)

ZSHRC_CONTENT='# ---- History ----
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

    if [[ "$(getent passwd "$(whoami)" | cut -d: -f7)" != "$(which zsh 2>/dev/null)" ]]; then
        PLAN+=("set_default_shell|设置 zsh 为默认 shell")
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
                print_step "设置 zsh 为默认 shell..."
                chsh -s "$(which zsh)" "$(whoami)"
                print_ok "默认 shell 已设为 zsh"
                ;;
            clone_plugin)
                local name url
                name="$(echo "${item}" | cut -d'|' -f3)"
                url="$(echo "${item}" | cut -d'|' -f4)"
                print_step "克隆插件 ${name}..."
                mkdir -p "${ZSH_PLUGIN_DIR}"
                git clone --depth=1 "${url}" "${ZSH_PLUGIN_DIR}/${name}"
                print_ok "插件 ${name} 安装完成"
                ;;
            write_zshrc)
                print_step "写入 .zshrc..."
                echo "${ZSHRC_CONTENT}" > "${ZSHRC}"
                print_ok ".zshrc 已更新"
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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/setup-zsh.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-zsh.sh
git commit -m "feat: add idempotent setup-zsh.sh with detect-confirm-execute pattern"
```

---

## Task 3: 重写 scripts/setup-ssh.sh（合并两个旧脚本）

**Files:**
- Create: `scripts/setup-ssh.sh`
- Delete: `setup_ssh.sh`, `setup_key_ssh.sh` (旧文件，最终统一删除)

- [ ] **Step 1: 创建 scripts/setup-ssh.sh**

```bash
#!/bin/bash
# @name: setup-ssh
# @description: SSH 密钥认证加固（禁用密码登录、更改端口、配置 UFW 防火墙）
# @category: 安全
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

SSH_PORT="22088"
SSHD_CONF="/etc/ssh/sshd_config.d/hardened.conf"
AUTH_KEYS="/root/.ssh/authorized_keys"

TARGET_SSHD_CONTENT="# Managed by vpssh setup-ssh
Port ${SSH_PORT}
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys"

# ---- 收集公钥 ----
collect_pubkey() {
    print_header "SSH 公钥"
    if [[ -f "${AUTH_KEYS}" ]] && [[ -s "${AUTH_KEYS}" ]]; then
        echo -e "当前已有公钥:"
        echo -e "${DIM}$(cat "${AUTH_KEYS}")${NC}"
        echo ""
        read -r -p "$(echo -e "${YELLOW}是否替换为新公钥？[y/N]: ${NC}")" replace </dev/tty
        if [[ ! "${replace}" =~ ^[Yy]$ ]]; then
            SSH_PUBKEY="__keep__"
            return
        fi
    fi

    echo -e "请粘贴你的 SSH 公钥（ssh-rsa/ssh-ed25519 ...）："
    read -r SSH_PUBKEY </dev/tty

    if [[ -z "${SSH_PUBKEY}" ]]; then
        print_err "公钥不能为空"
        exit 1
    fi

    if [[ ! "${SSH_PUBKEY}" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        print_warn "公钥格式看起来不对，请确认是否正确"
        if ! confirm "仍然继续？"; then
            exit 1
        fi
    fi
}

# ---- 检测阶段 ----
detect_state() {
    PLAN=()

    # SSH 目录和权限
    if [[ ! -d "/root/.ssh" ]] || [[ "$(stat -c '%a' /root/.ssh 2>/dev/null)" != "700" ]]; then
        PLAN+=("fix_ssh_dir|创建/修复 ~/.ssh 目录权限 (700)")
    fi

    # 公钥
    if [[ "${SSH_PUBKEY}" != "__keep__" ]]; then
        PLAN+=("write_pubkey|写入 SSH 公钥到 authorized_keys")
    fi

    # sshd_config.d 目录
    if [[ ! -d "/etc/ssh/sshd_config.d" ]]; then
        PLAN+=("create_sshd_dir|创建 /etc/ssh/sshd_config.d 目录")
    fi

    # 清理旧的冲突配置
    local has_old_conf=false
    for conf in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "${conf}" ]] || continue
        if [[ "${conf}" != "${SSHD_CONF}" ]]; then
            has_old_conf=true
            break
        fi
    done
    if [[ "${has_old_conf}" == "true" ]]; then
        PLAN+=("clean_old_conf|清理 sshd_config.d 下的旧配置文件")
    fi

    # sshd 配置
    if ! file_matches "${SSHD_CONF}" "${TARGET_SSHD_CONTENT}"; then
        PLAN+=("write_sshd_conf|写入 SSH 加固配置 (端口 ${SSH_PORT}，禁用密码)")
    fi

    # Include 指令
    if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
        PLAN+=("add_include|添加 Include 指令到 sshd_config")
    fi

    # 重启 sshd（如果有配置变更）
    local has_sshd_change=false
    for item in "${PLAN[@]}"; do
        if [[ "${item}" =~ write_sshd_conf|clean_old_conf|add_include ]]; then
            has_sshd_change=true
            break
        fi
    done
    if [[ "${has_sshd_change}" == "true" ]]; then
        PLAN+=("restart_sshd|重启 sshd 服务")
    fi

    # UFW
    if has_cmd ufw; then
        if ! ufw status | grep -q "${SSH_PORT}/tcp.*ALLOW" 2>/dev/null; then
            PLAN+=("ufw_allow|UFW 放行端口 ${SSH_PORT}/tcp")
        fi
        if ufw status | grep -q "22/tcp.*ALLOW" 2>/dev/null; then
            PLAN+=("ufw_deny_22|UFW 移除默认 22 端口规则")
        fi
    else
        PLAN+=("install_ufw|安装并配置 UFW 防火墙")
    fi
}

# ---- 展示计划 ----
show_plan() {
    print_header "SSH 加固配置计划"

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "SSH 已完全加固，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_add "${desc}"
    done

    # 已就绪项
    if [[ -d "/root/.ssh" ]] && [[ "$(stat -c '%a' /root/.ssh 2>/dev/null)" == "700" ]]; then
        print_plan_skip "~/.ssh 目录权限正确"
    fi
    if [[ "${SSH_PUBKEY}" == "__keep__" ]]; then
        print_plan_skip "authorized_keys 保持不变"
    fi
    if file_matches "${SSHD_CONF}" "${TARGET_SSHD_CONTENT}"; then
        print_plan_skip "SSH 配置已是目标状态"
    fi
    if has_cmd ufw && ufw status | grep -q "${SSH_PORT}/tcp.*ALLOW" 2>/dev/null; then
        print_plan_skip "UFW 已放行 ${SSH_PORT}"
    fi

    echo ""
    print_warn "请确保你有可用的 SSH 密钥，否则将无法登录！"
}

# ---- 执行阶段 ----
execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            fix_ssh_dir)
                print_step "修复 ~/.ssh 目录..."
                mkdir -p /root/.ssh
                chmod 700 /root/.ssh
                print_ok "~/.ssh 权限已设为 700"
                ;;
            write_pubkey)
                print_step "写入公钥..."
                echo "${SSH_PUBKEY}" > "${AUTH_KEYS}"
                chmod 600 "${AUTH_KEYS}"
                print_ok "公钥已写入 authorized_keys"
                ;;
            create_sshd_dir)
                print_step "创建 sshd_config.d..."
                mkdir -p /etc/ssh/sshd_config.d
                print_ok "目录已创建"
                ;;
            clean_old_conf)
                print_step "清理旧配置文件..."
                for conf in /etc/ssh/sshd_config.d/*.conf; do
                    [[ -f "${conf}" ]] || continue
                    if [[ "${conf}" != "${SSHD_CONF}" ]]; then
                        rm -f "${conf}"
                        print_ok "已删除: ${conf}"
                    fi
                done
                ;;
            write_sshd_conf)
                print_step "写入 SSH 加固配置..."
                echo "${TARGET_SSHD_CONTENT}" > "${SSHD_CONF}"
                print_ok "已写入: ${SSHD_CONF}"
                ;;
            add_include)
                print_step "添加 Include 指令..."
                echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
                print_ok "Include 指令已添加"
                ;;
            restart_sshd)
                print_step "重启 sshd..."
                if systemctl restart sshd; then
                    print_ok "sshd 已重启"
                else
                    print_err "sshd 重启失败，请手动检查"
                fi
                ;;
            install_ufw)
                print_step "安装 UFW..."
                apt update -y && apt install -y ufw
                ufw --force enable
                ufw allow "${SSH_PORT}/tcp"
                ufw delete allow 22/tcp 2>/dev/null || true
                print_ok "UFW 已安装并配置"
                ;;
            ufw_allow)
                print_step "UFW 放行端口 ${SSH_PORT}..."
                ufw allow "${SSH_PORT}/tcp"
                print_ok "已放行 ${SSH_PORT}/tcp"
                ;;
            ufw_deny_22)
                print_step "UFW 移除 22 端口..."
                ufw delete allow 22/tcp 2>/dev/null || true
                print_ok "已移除 22/tcp 规则"
                ;;
        esac
    done

    print_header "SSH 加固完成"
    echo -e "  ${GREEN}✓${NC} SSH 端口: ${BOLD}${SSH_PORT}${NC}"
    echo -e "  ${GREEN}✓${NC} 密码登录: ${BOLD}已禁用${NC}"
    echo -e "  ${GREEN}✓${NC} 认证方式: ${BOLD}仅密钥${NC}"
    echo ""
    print_warn "请用新端口测试连接，确认正常前不要关闭当前会话！"
}

# ---- 主流程 ----
collect_pubkey
detect_state
show_plan
if confirm; then
    execute_plan
else
    echo "已取消操作"
fi
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/setup-ssh.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-ssh.sh
git commit -m "feat: add idempotent setup-ssh.sh with key-only auth hardening"
```

---

## Task 4: 重写 scripts/configure-dns.sh

**Files:**
- Create: `scripts/configure-dns.sh`
- Delete: `configure_dns.sh` (旧文件)

- [ ] **Step 1: 创建 scripts/configure-dns.sh**

核心变更：
- 递归 `select_dns` 改为 `while true` 循环
- 所有 `read` 加 `-r`
- 所有 `[ ]` 改 `[[ ]]`，`==` 统一
- 移除 `clear` 避免管道问题
- 变量全部加引号
- 引入 `detect → show → confirm → execute` 模式
- DNS 测试阶段为只读操作，不需确认；仅在"应用 DNS"阶段走确认流程

```bash
#!/bin/bash
# @name: configure-dns
# @description: DNS 解析检测与优化（测试多 DNS 服务器，可切换配置）
# @category: 网络
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

DNS_SYSTEM=""
CLOUD_ENV=""
MAIN_INTERFACE=""
PRIMARY_DNS=""
SECONDARY_DNS=""
DNS_PROVIDER=""

# ---- 检测 DNS 环境 ----
detect_dns_system() {
    print_header "检测 DNS 环境"

    if systemctl is-active systemd-resolved &>/dev/null; then
        DNS_SYSTEM="systemd-resolved"
        print_ok "系统使用 systemd-resolved"
    elif [[ -L /etc/resolv.conf ]] && [[ "$(readlink /etc/resolv.conf)" == */NetworkManager/* ]]; then
        DNS_SYSTEM="networkmanager"
        print_ok "系统使用 NetworkManager"
    else
        DNS_SYSTEM="traditional"
        print_ok "系统使用传统 /etc/resolv.conf"
    fi

    # 当前 DNS
    echo -e "\n当前 DNS 服务器:"
    if [[ "${DNS_SYSTEM}" == "systemd-resolved" ]] && has_cmd resolvectl; then
        resolvectl status 2>/dev/null | grep "DNS Server" || true
    else
        grep "nameserver" /etc/resolv.conf || true
    fi

    # 主网络接口
    MAIN_INTERFACE="$(ip route | grep default | awk '{print $5}' | head -n 1)" || true
    if [[ -n "${MAIN_INTERFACE}" ]]; then
        print_ok "主网络接口: ${MAIN_INTERFACE}"
    else
        print_warn "无法自动检测网络接口"
        read -r -p "请输入网络接口名称 (如 ens5, eth0): " MAIN_INTERFACE </dev/tty
    fi

    # 云环境
    if curl -s --connect-timeout 2 --max-time 3 http://100.100.100.200/latest/meta-data/ &>/dev/null; then
        CLOUD_ENV="alicloud"
        print_ok "检测到阿里云环境"
    elif curl -s --connect-timeout 2 --max-time 3 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        CLOUD_ENV="aws"
        print_ok "检测到 AWS 环境"
    else
        CLOUD_ENV="unknown"
        print_ok "未检测到已知云环境"
    fi
}

# ---- 测试 DNS 解析（只读操作） ----
test_dns_resolution() {
    print_header "DNS 解析测试"

    local test_domain="www.google-analytics.com"

    if ! has_cmd dig; then
        print_step "安装 dig 工具..."
        apt update -qq && apt install -y dnsutils > /dev/null 2>&1 || true
    fi

    if ! has_cmd dig; then
        print_warn "dig 不可用，跳过 DNS 测试"
        return
    fi

    local servers=("8.8.8.8|Google DNS" "1.1.1.1|Cloudflare DNS")
    if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
        servers+=("100.100.2.136|阿里云内网 DNS")
    fi

    for entry in "${servers[@]}"; do
        local ip="${entry%%|*}"
        local name="${entry##*|}"
        echo -e "\n  ${BOLD}${name}${NC} (${ip}):"
        local result
        result="$(dig +short "${test_domain}" @"${ip}" 2>/dev/null)" || true
        if [[ -z "${result}" ]]; then
            print_err "  无法解析"
        else
            echo -e "    解析结果: ${BLUE}${result}${NC}"
        fi
    done
}

# ---- 选择 DNS ----
select_dns() {
    print_header "选择 DNS 服务器"
    while true; do
        echo -e "  ${BOLD}1)${NC} Cloudflare DNS (1.1.1.1, 1.0.0.1)"
        echo -e "  ${BOLD}2)${NC} Google DNS (8.8.8.8, 8.8.4.4)"
        if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
            echo -e "  ${BOLD}3)${NC} 阿里云内网 DNS (100.100.2.136, 100.100.2.138)"
            echo -e "  ${BOLD}4)${NC} 自定义"
            echo -e "  ${BOLD}0)${NC} 退出"
        else
            echo -e "  ${BOLD}3)${NC} 自定义"
            echo -e "  ${BOLD}0)${NC} 退出"
        fi

        read -r -p "$(echo -e "\n${CYAN}请选择: ${NC}")" choice </dev/tty
        case "${choice}" in
            1) PRIMARY_DNS="1.1.1.1"; SECONDARY_DNS="1.0.0.1"; DNS_PROVIDER="Cloudflare"; return ;;
            2) PRIMARY_DNS="8.8.8.8"; SECONDARY_DNS="8.8.4.4"; DNS_PROVIDER="Google"; return ;;
            3)
                if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
                    PRIMARY_DNS="100.100.2.136"; SECONDARY_DNS="100.100.2.138"; DNS_PROVIDER="阿里云内网"; return
                else
                    read -r -p "主 DNS: " PRIMARY_DNS </dev/tty
                    read -r -p "辅助 DNS: " SECONDARY_DNS </dev/tty
                    DNS_PROVIDER="自定义"; return
                fi
                ;;
            4)
                if [[ "${CLOUD_ENV}" == "alicloud" ]]; then
                    read -r -p "主 DNS: " PRIMARY_DNS </dev/tty
                    read -r -p "辅助 DNS: " SECONDARY_DNS </dev/tty
                    DNS_PROVIDER="自定义"; return
                else
                    print_err "无效选项"
                fi
                ;;
            0) echo "退出"; exit 0 ;;
            *) print_err "无效选项，请重试" ;;
        esac
    done
}

# ---- 展示并确认 DNS 变更计划 ----
show_dns_plan() {
    print_header "DNS 变更计划"
    print_plan_change "DNS 提供商: ${DNS_PROVIDER}"
    print_plan_change "主 DNS: ${PRIMARY_DNS}"
    print_plan_change "辅 DNS: ${SECONDARY_DNS}"
    print_plan_change "配置方式: ${DNS_SYSTEM}"
}

# ---- 应用 DNS ----
apply_dns() {
    case "${DNS_SYSTEM}" in
        systemd-resolved)
            if has_cmd resolvectl; then
                print_step "通过 resolvectl 配置 DNS..."
                if resolvectl dns "${MAIN_INTERFACE}" "${PRIMARY_DNS}" "${SECONDARY_DNS}"; then
                    systemctl restart systemd-resolved
                    print_ok "systemd-resolved 已更新"
                else
                    print_warn "resolvectl 失败，回退到配置文件方式..."
                    apply_resolved_conf
                fi
            else
                apply_resolved_conf
            fi
            ;;
        networkmanager)
            if has_cmd nmcli; then
                local conn
                conn="$(nmcli -g NAME con show --active | head -n 1)" || true
                if [[ -n "${conn}" ]]; then
                    print_step "通过 NetworkManager 配置 DNS..."
                    nmcli con mod "${conn}" ipv4.dns "${PRIMARY_DNS} ${SECONDARY_DNS}"
                    nmcli con up "${conn}"
                    print_ok "NetworkManager 已更新"
                else
                    apply_resolv_conf
                fi
            else
                apply_resolv_conf
            fi
            ;;
        *)
            apply_resolv_conf
            ;;
    esac
}

apply_resolved_conf() {
    print_step "写入 /etc/systemd/resolved.conf..."
    [[ -f /etc/systemd/resolved.conf ]] && cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=${PRIMARY_DNS} ${SECONDARY_DNS}
FallbackDNS=
EOF
    systemctl restart systemd-resolved
    print_ok "resolved.conf 已更新"
}

apply_resolv_conf() {
    print_step "写入 /etc/resolv.conf..."
    [[ -f /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]] && cp /etc/resolv.conf /etc/resolv.conf.bak
    [[ -L /etc/resolv.conf ]] && rm /etc/resolv.conf

    local content="# Managed by vpssh configure-dns
nameserver ${PRIMARY_DNS}"
    [[ -n "${SECONDARY_DNS}" ]] && content="${content}
nameserver ${SECONDARY_DNS}"
    content="${content}
options edns0"
    echo "${content}" > /etc/resolv.conf
    print_ok "/etc/resolv.conf 已更新"
}

# ---- 验证 ----
verify_dns() {
    print_header "验证新 DNS"
    sleep 1
    for domain in "www.google.com" "youtube.com"; do
        local result
        result="$(dig +short "${domain}" 2>/dev/null)" || true
        if [[ -n "${result}" ]]; then
            print_ok "${domain} → ${result}"
        else
            print_err "${domain} 解析失败"
        fi
    done
}

# ---- 主流程 ----
detect_dns_system
test_dns_resolution
select_dns
show_dns_plan
if confirm; then
    apply_dns
    verify_dns
    print_header "DNS 配置完成"
    echo -e "恢复方法:"
    echo -e "  systemd-resolved: ${CYAN}cp /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf && systemctl restart systemd-resolved${NC}"
    echo -e "  传统方式: ${CYAN}cp /etc/resolv.conf.bak /etc/resolv.conf${NC}"
else
    echo "已取消操作"
fi
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/configure-dns.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/configure-dns.sh
git commit -m "feat: add idempotent configure-dns.sh with loop-based menu and confirm pattern"
```

---

## Task 5: 重写 scripts/check-docker-logs.sh

**Files:**
- Create: `scripts/check-docker-logs.sh`
- Delete: `docker_logs_check.sh` (旧文件)

- [ ] **Step 1: 创建 scripts/check-docker-logs.sh**

此脚本为只读检查脚本，无需"确认→执行"流程，天然幂等。重点优化：变量加引号、检查 docker 是否存在、用 `numfmt` 简化。

```bash
#!/bin/bash
# @name: check-docker-logs
# @description: 检查 Docker 日志配置及磁盘空间占用情况
# @category: 运维
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

if ! has_cmd docker; then
    print_err "未找到 docker 命令，请先安装 Docker"
    exit 1
fi

# ---- Docker 日志驱动配置 ----
print_header "Docker 日志驱动配置"

if docker_info="$(docker info --format '{{json .}}' 2>/dev/null)"; then
    log_driver="$(echo "${docker_info}" | grep -o '"LoggingDriver":"[^"]*"' | cut -d':' -f2 | tr -d '"')"
    echo -e "  日志驱动: ${BOLD}${log_driver}${NC}"

    daemon_config="/etc/docker/daemon.json"
    if [[ -f "${daemon_config}" ]]; then
        echo -e "  daemon.json 日志相关配置:"
        grep -i "log" "${daemon_config}" | sed 's/^/    /' || true
    else
        print_warn "未找到 daemon.json"
    fi
else
    print_err "无法获取 Docker 信息"
fi

# ---- 各容器日志 ----
print_header "各容器日志大小"

containers="$(docker ps -a --format "{{.ID}}:{{.Names}}")" || true

if [[ -z "${containers}" ]]; then
    print_warn "未找到任何容器"
else
    total_size=0

    printf "  %-25s %-15s %-40s %s\n" "容器名称" "日志大小" "日志路径" "日志配置"
    printf "  %-25s %-15s %-40s %s\n" "-------------------------" "---------------" "----------------------------------------" "--------"

    while IFS=: read -r id name; do
        log_config="$(docker inspect --format='{{json .HostConfig.LogConfig}}' "${id}" 2>/dev/null)" || true
        log_type="$(echo "${log_config}" | grep -o '"Type":"[^"]*"' | cut -d':' -f2 | tr -d '"')" || true
        log_path="$(docker inspect --format='{{.LogPath}}' "${id}" 2>/dev/null)" || true

        if [[ -f "${log_path}" ]]; then
            size="$(du -h "${log_path}" 2>/dev/null | cut -f1)"
            size_bytes="$(du -b "${log_path}" 2>/dev/null | cut -f1)"
            total_size=$((total_size + size_bytes))
        else
            size="N/A"
        fi

        printf "  %-25s %-15s %-40s %s\n" "${name:0:25}" "${size}" "${log_path:0:40}" "${log_type}"
    done <<< "${containers}"

    if has_cmd numfmt; then
        total_h="$(numfmt --to=iec "${total_size}")"
    else
        total_h="${total_size} B"
    fi
    echo -e "\n  ${YELLOW}容器日志总占用: ${BOLD}${total_h}${NC}"
fi

# ---- Docker 磁盘使用 ----
print_header "Docker 磁盘使用"
docker system df 2>/dev/null | sed 's/^/  /'

# ---- 服务器磁盘 ----
print_header "服务器磁盘使用"
df -h | grep -v "tmpfs\|devtmpfs" | sed 's/^/  /'

echo -e "\n  /var 下占用 Top 5:"
du -sh /var/* 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'

if [[ -d "/var/lib/docker" ]]; then
    echo -e "\n  /var/lib/docker 下占用 Top 5:"
    du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'
fi

# ---- 优化建议 ----
print_header "优化建议"
echo -e "  1. 在 /etc/docker/daemon.json 添加日志限制:"
echo -e '     {"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}'
echo -e ""
echo -e "  2. 清理命令:"
echo -e "     docker image prune -a    # 删除未使用镜像"
echo -e "     docker system prune      # 一键清理(慎用)"
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/check-docker-logs.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/check-docker-logs.sh
git commit -m "feat: add check-docker-logs.sh with quoted vars and docker precheck"
```

---

## Task 6: 重写 scripts/configure-nezha.sh

**Files:**
- Create: `scripts/configure-nezha.sh`
- Delete: `nezha.sh` (旧文件)

- [ ] **Step 1: 创建 scripts/configure-nezha.sh**

```bash
#!/bin/bash
# @name: configure-nezha
# @description: 哪吒探针安全加固（禁用自动更新、远程命令执行）
# @category: 监控
# @requires: root
# @idempotent: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source /tmp/vpssh-common.sh

require_root

SERVICE_FILE="/etc/systemd/system/nezha-agent.service"

# ---- 检测阶段 ----
detect_state() {
    PLAN=()

    if ! systemctl list-unit-files 2>/dev/null | grep -q nezha-agent; then
        print_err "未检测到 nezha-agent 服务"
        exit 1
    fi

    if [[ ! -f "${SERVICE_FILE}" ]]; then
        print_err "未找到服务配置文件: ${SERVICE_FILE}"
        exit 1
    fi

    # 提取当前参数
    CURRENT_SERVER="$(grep "ExecStart" "${SERVICE_FILE}" | grep -o '"-s"[[:space:]]*"[^"]*"' | cut -d'"' -f4)" || true
    CURRENT_PASSWORD="$(grep "ExecStart" "${SERVICE_FILE}" | grep -o '"-p"[[:space:]]*"[^"]*"' | cut -d'"' -f4)" || true

    if [[ -z "${CURRENT_SERVER}" ]] || [[ -z "${CURRENT_PASSWORD}" ]]; then
        print_err "无法从配置中提取服务器地址或密码"
        exit 1
    fi

    # 构建目标配置
    TARGET_EXEC="ExecStart=/opt/nezha/agent/nezha-agent \"-s\" \"${CURRENT_SERVER}\" \"-p\" \"${CURRENT_PASSWORD}\" --disable-auto-update --disable-force-update --disable-command-execute --report-delay 3"
    CURRENT_EXEC="$(grep "^ExecStart=" "${SERVICE_FILE}")"

    if [[ "${CURRENT_EXEC}" != "${TARGET_EXEC}" ]]; then
        PLAN+=("rewrite_service|重写 systemd 服务配置（加固参数）")
    fi
}

# ---- 展示计划 ----
show_plan() {
    print_header "哪吒探针加固计划"

    echo -e "  服务器: ${BOLD}${CURRENT_SERVER}${NC}"
    echo -e "  密码: ${BOLD}${CURRENT_PASSWORD}${NC}"
    echo ""

    if [[ ${#PLAN[@]} -eq 0 ]]; then
        print_skip "配置已是目标状态，无需操作"
        exit 0
    fi

    for item in "${PLAN[@]}"; do
        local desc
        desc="$(echo "${item}" | cut -d'|' -f2)"
        print_plan_change "${desc}"
    done

    echo ""
    echo -e "  加固项:"
    echo -e "    ${GREEN}✓${NC} --disable-auto-update"
    echo -e "    ${GREEN}✓${NC} --disable-force-update"
    echo -e "    ${GREEN}✓${NC} --disable-command-execute"
    echo -e "    ${GREEN}✓${NC} --report-delay 3"
}

# ---- 执行阶段 ----
execute_plan() {
    for item in "${PLAN[@]}"; do
        local action
        action="$(echo "${item}" | cut -d'|' -f1)"

        case "${action}" in
            rewrite_service)
                print_step "备份当前配置..."
                cp "${SERVICE_FILE}" "${SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
                print_ok "已备份"

                print_step "写入加固配置..."
                cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Nezha Agent
ConditionFileIsExecutable=/opt/nezha/agent/nezha-agent

[Service]
StartLimitInterval=5
StartLimitBurst=10
${TARGET_EXEC}
WorkingDirectory=/root
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/nezha-agent

[Install]
WantedBy=multi-user.target
EOF
                print_ok "服务配置已更新"

                print_step "重载 systemd 并重启服务..."
                systemctl daemon-reload
                if systemctl restart nezha-agent; then
                    print_ok "nezha-agent 已重启"
                else
                    print_err "nezha-agent 重启失败"
                fi

                print_step "检查服务状态..."
                systemctl is-active nezha-agent && print_ok "服务运行中" || print_err "服务未运行"
                ;;
        esac
    done
}

# ---- 主流程 ----
detect_state
show_plan
if confirm; then
    execute_plan
    print_header "哪吒探针加固完成"
else
    echo "已取消操作"
fi
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/configure-nezha.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/configure-nezha.sh
git commit -m "feat: add idempotent configure-nezha.sh with hardening flags"
```

---

## Task 7: 重写 scripts/install-tools.sh

**Files:**
- Create: `scripts/install-tools.sh`
- Delete: `install_tools.sh` (旧文件)

- [ ] **Step 1: 创建 scripts/install-tools.sh**

```bash
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

# ---- 检测发行版 ----
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

    case "${DISTRO}" in
        debian)
            apt update -y
            apt install -y "${PACKAGES_TO_INSTALL[@]}"
            ;;
        redhat)
            dnf install -y "${PACKAGES_TO_INSTALL[@]}" 2>/dev/null || yum install -y "${PACKAGES_TO_INSTALL[@]}"
            ;;
        arch)
            pacman -Sy --noconfirm "${PACKAGES_TO_INSTALL[@]}"
            ;;
        alpine)
            apk update && apk add "${PACKAGES_TO_INSTALL[@]}"
            ;;
    esac

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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/install-tools.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/install-tools.sh
git commit -m "feat: add idempotent install-tools.sh with distro detection"
```

---

## Task 8: 创建 menu.sh 入口脚本

**Files:**
- Create: `menu.sh`

- [ ] **Step 1: 创建 menu.sh**

```bash
#!/bin/bash
# @name: menu
# @description: VPS 工具集统一入口菜单（支持 curl | bash 远程执行）
# @category: 入口
# @requires: none
# @idempotent: true

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/hexsean/vpssh/main"

# ---- 内联颜色（入口脚本不依赖 common.sh） ----
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

    echo -e "\n${CYAN}---> 下载 lib/common.sh ...${NC}"
    if ! curl -fsSL "${REPO_RAW}/lib/common.sh" -o /tmp/vpssh-common.sh; then
        echo -e "${RED}下载 common.sh 失败${NC}"
        return 1
    fi

    echo -e "${CYAN}---> 下载 scripts/${script_file} ...${NC}"
    if ! curl -fsSL "${REPO_RAW}/scripts/${script_file}" -o "/tmp/vpssh-${script_file}"; then
        echo -e "${RED}下载 ${script_file} 失败${NC}"
        return 1
    fi

    echo -e "${CYAN}---> 执行 ${script_file} ...${NC}\n"
    bash "/tmp/vpssh-${script_file}"

    # 清理
    rm -f "/tmp/vpssh-${script_file}" /tmp/vpssh-common.sh
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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n menu.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add menu.sh
git commit -m "feat: add menu.sh unified entry point with curl|bash support"
```

---

## Task 9: 删除旧文件并最终验证

**Files:**
- Delete: `setup-zsh.sh`, `setup_ssh.sh`, `setup_key_ssh.sh`, `configure_dns.sh`, `docker_logs_check.sh`, `nezha.sh`, `install_tools.sh`

- [ ] **Step 1: 删除旧脚本**

```bash
git rm setup-zsh.sh setup_ssh.sh setup_key_ssh.sh configure_dns.sh docker_logs_check.sh nezha.sh install_tools.sh
```

- [ ] **Step 2: 语法验证所有新脚本**

```bash
for f in lib/common.sh scripts/*.sh menu.sh; do
    echo "Checking $f..."
    bash -n "$f" && echo "  OK" || echo "  FAIL"
done
```
Expected: 所有文件显示 OK

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor: remove legacy scripts, complete migration to new structure"
```

---

## 执行完成标志

全部任务完成后，项目结构应为：

```
vpssh/
├── menu.sh
├── lib/
│   └── common.sh
├── scripts/
│   ├── setup-zsh.sh
│   ├── setup-ssh.sh
│   ├── configure-dns.sh
│   ├── check-docker-logs.sh
│   ├── configure-nezha.sh
│   └── install-tools.sh
├── docs/
│   └── superpowers/
│       └── plans/
│           └── 2026-04-05-script-refactor.md
└── README.md
```

使用方式：

```bash
# 远程一键菜单
bash <(curl -fsSL https://raw.githubusercontent.com/hexsean/vpssh/main/menu.sh)

# 本地执行单个脚本
cd vpssh && bash scripts/setup-ssh.sh
```
