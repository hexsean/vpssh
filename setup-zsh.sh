#!/bin/bash
# 一键配置 zsh 环境
# 用法: curl -fsSL <raw_url> | bash

set -e

echo "=== 更新 apt ==="
sudo apt update -y && sudo apt upgrade -y

echo "=== 安装 zsh 和 git ==="
sudo apt install -y zsh git

echo "=== 设置 zsh 为当前用户默认 shell ==="
sudo chsh -s "$(which zsh)" "$(whoami)"

echo "=== 安装插件 ==="
mkdir -p ~/.zsh/plugins
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions 2>/dev/null || echo "autosuggestions 已存在，跳过"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting 2>/dev/null || echo "syntax-highlighting 已存在，跳过"
git clone --depth=1 https://github.com/agkozak/zsh-z ~/.zsh/plugins/zsh-z 2>/dev/null || echo "zsh-z 已存在，跳过"

echo "=== 写入 .zshrc ==="
cat << 'EOF' > ~/.zshrc
# ---- History ----
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# ---- Completion ----
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# ---- Plugins ----
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/plugins/zsh-z/zsh-z.plugin.zsh

# ---- Prompt ----
PROMPT='%F{cyan}%n@%m%f:%F{green}%~%f %# '

# ---- Aliases ----
alias ll='ls -alF'
alias la='ls -A'
EOF

echo "=== 完成! ==="
echo "重新登录或执行 zsh 即可生效"
exec zsh
