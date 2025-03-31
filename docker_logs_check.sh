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
    printf "   %-25s %-15s %-40s %s\n" "容器名称" "日志大小" "日志路径" "日志配置"
    printf "   %-25s %-15s %-40s %s\n" "-------------------------" "---------------" "----------------------------------------" "----------------"

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
            size_bytes=0
        fi

        # 显示结果
        printf "   %-25s %-15s %-40s %s\n" "${name:0:25}" "$size" "${log_path:0:40}" "$log_driver"
    done

    # 无需bc，使用内置bash计算
    if [ $total_size -ge 1073741824 ]; then
        total_size_h="$((total_size / 1073741824)).$((total_size % 1073741824 * 100 / 1073741824)) GB"
    elif [ $total_size -ge 1048576 ]; then
        total_size_h="$((total_size / 1048576)).$((total_size % 1048576 * 100 / 1048576)) MB"
    elif [ $total_size -ge 1024 ]; then
        total_size_h="$((total_size / 1024)).$((total_size % 1024 * 100 / 1024)) KB"
    else
        total_size_h="${total_size} B"
    fi

    echo -e "\n   ${YELLOW}容器日志总占用空间: $total_size_h${NC}"
fi

echo -e "\n${BLUE}[3] Docker 系统磁盘使用情况:${NC}"
# 使用管道并确保每行前有空格
docker system df | sed 's/^/   /'
echo -e "\n   ${YELLOW}详细信息:${NC}"
docker system df -v | grep -E '(^TYPE|^CONTAINER|^Images|^Containers|^Local Volumes|^Build Cache)' | sed 's/^/   /'

# 4. 检测服务器磁盘空间使用情况（不安装新依赖）
echo -e "\n${BLUE}[4] 服务器磁盘空间使用情况:${NC}"
echo -e "   ${YELLOW}分区使用情况:${NC}"
df -h | grep -v "tmpfs\|devtmpfs\|/dev" | sed 's/^/   /'

echo -e "\n   ${YELLOW}占用空间最大的目录:${NC}"
echo -e "   (仅检查关键目录以节省资源...)"
echo -e "   大小\t\t目录"
echo -e "   --------------------\t-------------------------------"
# 仅检查主要目录而不是扫描整个文件系统
for dir in /var /usr /home /opt /root /etc /tmp; do
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | sed 's/^/   /'
    fi
done

echo -e "\n   ${YELLOW}/var 目录下占用空间最大的目录:${NC}"
if [ -d "/var" ]; then
    # 限制du的深度，避免遍历所有文件
    du -sh /var/* 2>/dev/null | sort -rh | head -5 | sed 's/^/   /'
else
    echo -e "   ${RED}/var 目录不存在${NC}"
fi

if [ -d "/var/lib/docker" ]; then
    echo -e "\n   ${YELLOW}/var/lib/docker 目录空间占用:${NC}"
    du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -5 | sed 's/^/   /'

    # 检查Docker容器存储
    echo -e "\n   ${YELLOW}Docker容器存储空间(按大小排序):${NC}"
    du -sh /var/lib/docker/containers/* 2>/dev/null | sort -rh | head -5 | sed 's/^/   /'
else
    echo -e "\n   ${RED}/var/lib/docker 目录不存在或无法访问${NC}"
fi

# 仅在非关键路径查找大文件，避免过度消耗资源
echo -e "\n   ${YELLOW}查找大文件(>100MB)限定在/var/log和/tmp:${NC}"
find /var/log /tmp -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -rh | head -5 | awk '{print "   " $5 "\t" $9}'

echo -e "\n${GREEN}===== 查询完成 =====${NC}"

# 添加优化建议
echo -e "\n${BLUE}[5] 优化建议:${NC}"
echo -e "   ${YELLOW}1. Docker 日志优化:${NC}"
echo -e "      - 在 /etc/docker/daemon.json 中添加日志限制配置:"
echo -e "        {"
echo -e "          \"log-driver\": \"json-file\","
echo -e "          \"log-opts\": {"
echo -e "            \"max-size\": \"10m\","
echo -e "            \"max-file\": \"3\""
echo -e "          }"
echo -e "        }"

echo -e "\n   ${YELLOW}2. 快速释放空间命令:${NC}"
echo -e "      - 删除未使用的镜像:        docker image prune"
echo -e "      - 删除所有未使用的镜像:    docker image prune -a"
echo -e "      - 删除已停止的容器:        docker container prune"
echo -e "      - 删除未使用的卷:          docker volume prune"
echo -e "      - 一键清理(慎用):          docker system prune"
