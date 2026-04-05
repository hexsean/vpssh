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

print_header "Docker 日志驱动配置"

if log_driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)"; then
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

print_header "各容器日志大小"

containers="$(docker ps -a --format "{{.ID}}:{{.Names}}")" || true

if [[ -z "${containers}" ]]; then
    print_warn "未找到任何容器"
else
    total_size=0

    printf "  %-25s %-15s %-40s %s\n" "容器名称" "日志大小" "日志路径" "日志配置"
    printf "  %-25s %-15s %-40s %s\n" "-------------------------" "---------------" "----------------------------------------" "--------"

    while IFS=: read -r id name; do
        # 单次 inspect 获取日志类型和路径
        read -r log_type log_path < <(docker inspect \
            --format='{{.HostConfig.LogConfig.Type}} {{.LogPath}}' "${id}" 2>/dev/null) || true

        if [[ -f "${log_path}" ]]; then
            size_bytes="$(stat -c '%s' "${log_path}" 2>/dev/null)" || size_bytes=0
            total_size=$((total_size + size_bytes))
            if has_cmd numfmt; then
                size="$(numfmt --to=iec "${size_bytes}")"
            else
                size="${size_bytes} B"
            fi
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

print_header "Docker 磁盘使用"
docker system df 2>/dev/null | sed 's/^/  /'

print_header "服务器磁盘使用"
df -h | grep -v "tmpfs\|devtmpfs" | sed 's/^/  /'

echo -e "\n  /var 下占用 Top 5:"
du -sh /var/* 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'

if [[ -d "/var/lib/docker" ]]; then
    echo -e "\n  /var/lib/docker 下占用 Top 5:"
    du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'
fi

print_header "优化建议"
echo -e "  1. 在 /etc/docker/daemon.json 添加日志限制:"
echo -e '     {"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}'
echo -e ""
echo -e "  2. 清理命令:"
echo -e "     docker image prune -a    # 删除未使用镜像"
echo -e "     docker system prune      # 一键清理(慎用)"
