#!/bin/bash

# 检查是否有 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 设置下载目录为 root 目录下的 cf 目录
DOWNLOAD_DIR="/root/cf"

# 创建 cf 目录（如果不存在）
mkdir -p "${DOWNLOAD_DIR}"

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
    # 检查文件是否存在且非空
    if [ ! -s "${output}" ]; then
        echo "正在下载 ${output}..."
        if command -v curl >/dev/null 2>&1; then
            curl -L -o "${output}" "${url}"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "${output}" "${url}"
        else
            echo "错误: 请安装 curl 或 wget"
            return 1
        fi
        echo "下载完成: ${output}"
    else
        echo "文件已存在且非空，跳过下载: ${output}"
    fi
}

# 下载二进制文件
download_file "${BASE_URL}/${BINARY}" "${DOWNLOAD_DIR}/cf"
[ -f "${DOWNLOAD_DIR}/cf" ] && chmod +x "${DOWNLOAD_DIR}/cf"

# 下载 ipv4 文件
download_file "${BASE_URL}/ips-v4.txt" "${DOWNLOAD_DIR}/ipv4.txt"

# 下载 ipv6 文件
download_file "${BASE_URL}/ips-v6.txt" "${DOWNLOAD_DIR}/ipv6.txt"

# 下载 locations.json 文件
download_file "${BASE_URL}/locations.json" "${DOWNLOAD_DIR}/locations.json"

# 检查下载的文件是否为空
check_file() {
    local file="$1"
    if [ ! -s "$file" ]; then
        echo "警告: $file 是空文件，可能需要重新下载"
    fi
}

# 检查所有文件
check_file "${DOWNLOAD_DIR}/cf"
check_file "${DOWNLOAD_DIR}/ipv4.txt"
check_file "${DOWNLOAD_DIR}/ipv6.txt"
check_file "${DOWNLOAD_DIR}/locations.json"

echo "完成！文件位于 ${DOWNLOAD_DIR}/ 目录下"
echo "文件列表："
echo "1. cf (二进制文件，已设置执行权限)"
echo "2. ipv4.txt"
echo "3. ipv6.txt"
echo "4. locations.json"
