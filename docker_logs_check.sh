#!/bin/bash

# 设置输出颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

echo -e "${GREEN}===== Docker 日志配置及空间占用情况 =====${NC}\n"

# 1. 查询 Docker 守护进程日志配置
echo -e "${BLUE}[1] Docker 日志驱动配置:${NC}"
docker_info=$(docker info --format '{{json .}}' 2>/dev/null)
if [ $? -eq 0 ]; then
    log_driver=$(echo $docker_info | grep -o '"LoggingDriver":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    echo -e "   日志驱动: ${YELLOW}$log_driver${NC}"

    # 尝试获取日志配置
    daemon_config="/etc/docker/daemon.json"
    if [ -f "$daemon_config" ]; then
        echo -e "\n   daemon.json 配置文件内容:"
        cat "$daemon_config" | grep -i "log" | sed 's/^/   /'
    else
        echo -e "   ${YELLOW}未找到 daemon.json 配置文件${NC}"
    fi
else
    echo -e "   ${RED}无法获取 Docker 信息，请确认您有足够的权限${NC}"
fi

echo -e "\n${BLUE}[2] 各容器日志配置及大小:${NC}"
# 获取所有容器ID和名称
containers=$(docker ps -a --format "{{.ID}}:{{.Names}}")

if [ -z "$containers" ]; then
    echo -e "   ${YELLOW}未找到任何容器${NC}"
else
    # 计算容器日志总大小
    total_size=0

    # 表头
    printf "   %-20s %-15s %-40s %s\n" "容器名称" "日志大小" "日志路径" "日志配置"
    printf "   %-20s %-15s %-40s %s\n" "--------------------" "---------------" "----------------------------------------" "----------------"

    # 遍历每个容器
    for container in $containers; do
        id=$(echo $container | cut -d':' -f1)
        name=$(echo $container | cut -d':' -f2)

        # 获取容器日志配置
        log_config=$(docker inspect --format='{{json .HostConfig.LogConfig}}' $id 2>/dev/null)
        log_driver=$(echo $log_config | grep -o '"Type":"[^"]*"' | cut -d':' -f2 | tr -d '"')

        # 获取容器日志路径
        log_path=$(docker inspect --format='{{.LogPath}}' $id 2>/dev/null)

        # 获取日志大小
        if [ -f "$log_path" ]; then
            size=$(du -h "$log_path" 2>/dev/null | cut -f1)
            size_bytes=$(du -b "$log_path" 2>/dev/null | cut -f1)
            total_size=$((total_size + size_bytes))
        else
            size="无法访问"
        fi

        # 显示结果
        printf "   %-20s %-15s %-40s %s\n" "${name:0:20}" "$size" "${log_path:0:40}" "$log_driver"
    done

    # 转换总大小为人类可读格式
    if [ $total_size -ge 1073741824 ]; then
        total_size_h=$(echo "scale=2; $total_size/1073741824" | bc)" GB"
    elif [ $total_size -ge 1048576 ]; then
        total_size_h=$(echo "scale=2; $total_size/1048576" | bc)" MB"
    elif [ $total_size -ge 1024 ]; then
        total_size_h=$(echo "scale=2; $total_size/1024" | bc)" KB"
    else
        total_size_h="${total_size} B"
    fi

    echo -e "\n   ${YELLOW}容器日志总占用空间: $total_size_h${NC}"
fi

echo -e "\n${BLUE}[3] Docker 系统磁盘使用情况:${NC}"
docker system df -v | grep -E '(^SIZE|^CONTAINER|^Images|^Containers|^Local Volumes|^Build Cache)'

echo -e "\n${GREEN}===== 查询完成 =====${NC}"
