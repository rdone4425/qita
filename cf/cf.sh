#!/bin/bash

# 检查是否有 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 删除 root 目录下的 cf.sh
rm -f /root/cf.sh >/dev/null 2>&1

# 设置下载目录为 root 目录下的 cf 目录
DOWNLOAD_DIR="/root/cf"
mkdir -p "${DOWNLOAD_DIR}" >/dev/null 2>&1

# 检测系统架构
ARCH=$(uname -m)

# 将系统架构映射到仓库中的文件名
case ${ARCH} in
    x86_64)
        BINARY="amd64"
        ;;
    i386|i686)
        BINARY="386"
        ;;
    aarch64)
        BINARY="arm64"
        ;;
    armv7l|armv6l)
        BINARY="arm"
        ;;
    mips64)
        BINARY="mips64"
        ;;
    mips64le)
        BINARY="mips64le"
        ;;
    mipsle)
        BINARY="mipsle"
        ;;
    *)
        echo "不支持的系统架构: ${ARCH}"
        exit 1
        ;;
esac

# 代理 URL
PROXY_URL="https://git.442595.xyz/proxy/"
# 基础 URL
BASE_URL="${PROXY_URL}https://raw.githubusercontent.com/rdone4425/qita/main/cf"

# 下载文件函数
download_file() {
    local url="$1"
    local output="$2"
    if [ ! -s "${output}" ] >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1; then
            curl -s -L -o "${output}" "${url}" >/dev/null 2>&1
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "${output}" "${url}" >/dev/null 2>&1
        else
            echo "错误: 请安装 curl 或 wget"
            return 1
        fi
    fi
}

# 静默下载所有文件
download_file "${BASE_URL}/${BINARY}" "${DOWNLOAD_DIR}/cf" >/dev/null 2>&1
download_file "${BASE_URL}/ips-v4.txt" "${DOWNLOAD_DIR}/ipv4.txt" >/dev/null 2>&1
download_file "${BASE_URL}/ips-v6.txt" "${DOWNLOAD_DIR}/ipv6.txt" >/dev/null 2>&1
download_file "${BASE_URL}/locations.json" "${DOWNLOAD_DIR}/locations.json" >/dev/null 2>&1

# 静默检查文件
check_file() {
    local file="$1"
    [ ! -s "$file" ] && echo "警告: $file 下载失败" >/dev/null 2>&1
}

# 静默检查所有文件
check_file "${DOWNLOAD_DIR}/cf" >/dev/null 2>&1
check_file "${DOWNLOAD_DIR}/ipv4.txt" >/dev/null 2>&1
check_file "${DOWNLOAD_DIR}/ipv6.txt" >/dev/null 2>&1
check_file "${DOWNLOAD_DIR}/locations.json" >/dev/null 2>&1

[ -f "${DOWNLOAD_DIR}/cf" ] && chmod +x "${DOWNLOAD_DIR}/cf" >/dev/null 2>&1
echo "完成" && exit 0
