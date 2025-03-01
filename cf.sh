#!/bin/bash

# 脚本名称: cf_download.sh
# 描述: 检测系统架构并下载对应的Cloudflare客户端工具，提供IP优选功能
# 版本: 1.0

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 仓库URL
REPO_URL="https://github.com/rdone4425/qita/raw/main/cf"
# 代理URL前缀
PROXY_PREFIX="https://git.442595.xyz/proxy/"

# 安装目录
INSTALL_DIR="./cloudflare-client"

# 创建临时目录
TMP_DIR="/tmp/cf_download"
mkdir -p $TMP_DIR

# 获取本地IPv4地址 - BusyBox兼容版
get_local_ipv4() {
    local ipv4=""
    
    # 方法1: 使用ip命令 (BusyBox兼容)
    if command -v ip &> /dev/null; then
        ipv4=$(ip -4 addr | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -v "127.0.0.1" | awk '{print $2}' | head -n 1)
    fi
    
    # 方法2: 使用ifconfig命令 (BusyBox兼容)
    if [ -z "$ipv4" ] && command -v ifconfig &> /dev/null; then
        ipv4=$(ifconfig | grep -o "inet addr:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -v "127.0.0.1" | awk -F: '{print $2}' | head -n 1)
        if [ -z "$ipv4" ]; then
            ipv4=$(ifconfig | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -v "127.0.0.1" | awk '{print $2}' | head -n 1)
        fi
    fi
    
    # 方法3: 使用hostname命令
    if [ -z "$ipv4" ] && command -v hostname &> /dev/null; then
        ipv4=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # 方法4: 检查特定接口
    if [ -z "$ipv4" ]; then
        for iface in eth0 eth1 en0 ens33 enp0s3 br0 br-lan wlan0; do
            if ifconfig $iface 2>/dev/null | grep -q "inet "; then
                ipv4=$(ifconfig $iface | grep -o "inet addr:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | awk -F: '{print $2}')
                if [ -z "$ipv4" ]; then
                    ipv4=$(ifconfig $iface | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | awk '{print $2}')
                fi
                if [ ! -z "$ipv4" ]; then
                    break
                fi
            fi
        done
    fi
    
    # 输出结果
    if [ -z "$ipv4" ]; then
        echo "无IPv4地址"
    else
        echo "$ipv4"
    fi
}

# 获取本地IPv6地址 - BusyBox兼容版
get_local_ipv6() {
    local ipv6=""
    
    # 方法1: 使用ip命令 (BusyBox兼容)
    if command -v ip &> /dev/null; then
        ipv6=$(ip -6 addr | grep -o "inet6 [0-9a-fA-F:]*" | grep -v "::1" | awk '{print $2}' | head -n 1)
    fi
    
    # 方法2: 使用ifconfig命令 (BusyBox兼容)
    if [ -z "$ipv6" ] && command -v ifconfig &> /dev/null; then
        ipv6=$(ifconfig | grep -o "inet6 addr: [0-9a-fA-F:]*" | grep -v "::1" | awk '{print $3}' | head -n 1)
        if [ -z "$ipv6" ]; then
            ipv6=$(ifconfig | grep -o "inet6 [0-9a-fA-F:]*" | grep -v "::1" | awk '{print $2}' | head -n 1)
        fi
    fi
    
    # 方法3: 检查特定接口
    if [ -z "$ipv6" ]; then
        for iface in eth0 eth1 en0 ens33 enp0s3 br0 br-lan wlan0; do
            if ifconfig $iface 2>/dev/null | grep -q "inet6 "; then
                ipv6=$(ifconfig $iface | grep -o "inet6 addr: [0-9a-fA-F:]*" | awk '{print $3}')
                if [ -z "$ipv6" ]; then
                    ipv6=$(ifconfig $iface | grep -o "inet6 [0-9a-fA-F:]*" | awk '{print $2}')
                fi
                if [ ! -z "$ipv6" ]; then
                    break
                fi
            fi
        done
    fi
    
    # 输出结果
    if [ -z "$ipv6" ]; then
        echo "无IPv6地址"
    else
        echo "$ipv6"
    fi
}

# 显示菜单
show_menu() {
    clear
    
    echo -e "${BLUE}=== Cloudflare IP优选工具 ===${NC}"
    echo
    echo -e "${CYAN}1.${NC} IPv4优选 (仅优选IPv4地址)"
    echo -e "${CYAN}2.${NC} IPv6优选 (仅优选IPv6地址)"
    echo -e "${CYAN}3.${NC} 组合优选 (同时优选IPv4和IPv6地址)"
    echo -e "${CYAN}0.${NC} 退出"
    echo
    echo -n "请输入选项 [0-3]: "
}

# 检测系统架构
detect_arch() {
    echo "正在检测系统架构..."
    ARCH=$(uname -m)
    OS=$(uname -s)

    # 确定下载的文件名
    case $ARCH in
        x86_64)
            CF_ARCH="amd64"
            ;;
        i386|i686)
            CF_ARCH="386"
            ;;
        armv7*|armv6*|armv5*)
            CF_ARCH="arm"
            ;;
        aarch64|armv8*|arm64)
            CF_ARCH="arm64"
            ;;
        mips64)
            CF_ARCH="mips64"
            ;;
        mips64le)
            CF_ARCH="mips64le"
            ;;
        mipsle)
            CF_ARCH="mipsle"
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构: $ARCH${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}检测到系统架构: $ARCH (将使用 $CF_ARCH 版本)${NC}"
}

# 下载客户端和配置文件
download_client() {
    # 检测系统架构
    detect_arch
    
    # 在当前目录创建新目录
    mkdir -p "$INSTALL_DIR"

    # 下载二进制文件
    echo "正在下载 Cloudflare 客户端..."
    CF_URL="${PROXY_PREFIX}${REPO_URL}/${CF_ARCH}"
    CF_PATH="$TMP_DIR/cf"

    if command -v curl &> /dev/null; then
        curl -L -o "$CF_PATH" "$CF_URL"
        DOWNLOAD_STATUS=$?
    elif command -v wget &> /dev/null; then
        wget -O "$CF_PATH" "$CF_URL"
        DOWNLOAD_STATUS=$?
    else
        echo -e "${RED}错误: 需要 curl 或 wget 来下载文件，但都未安装。${NC}"
        rm -rf "$INSTALL_DIR"
        return 1
    fi

    if [ $DOWNLOAD_STATUS -ne 0 ]; then
        echo -e "${RED}通过代理下载失败，尝试直接下载...${NC}"
        
        if command -v curl &> /dev/null; then
            curl -L -o "$CF_PATH" "${REPO_URL}/${CF_ARCH}"
            DOWNLOAD_STATUS=$?
        elif command -v wget &> /dev/null; then
            wget -O "$CF_PATH" "${REPO_URL}/${CF_ARCH}"
            DOWNLOAD_STATUS=$?
        fi
        
        if [ $DOWNLOAD_STATUS -ne 0 ]; then
            echo -e "${RED}下载失败，请检查网络连接或仓库地址。${NC}"
            rm -rf "$INSTALL_DIR"
            return 1
        fi
    fi

    # 下载配置文件
    echo "正在下载配置文件..."
    CONFIG_FILES=("ips-v4.txt" "ips-v6.txt" "locations.json")

    for file in "${CONFIG_FILES[@]}"; do
        CONFIG_URL="${PROXY_PREFIX}${REPO_URL}/${file}"
        
        if command -v curl &> /dev/null; then
            curl -L -o "$TMP_DIR/$file" "$CONFIG_URL"
            DL_STATUS=$?
        elif command -v wget &> /dev/null; then
            wget -O "$TMP_DIR/$file" "$CONFIG_URL"
            DL_STATUS=$?
        fi
        
        if [ $DL_STATUS -ne 0 ]; then
            echo -e "${YELLOW}通过代理下载配置文件 $file 失败，尝试直接下载...${NC}"
            
            if command -v curl &> /dev/null; then
                curl -L -o "$TMP_DIR/$file" "${REPO_URL}/${file}"
            elif command -v wget &> /dev/null; then
                wget -O "$TMP_DIR/$file" "${REPO_URL}/${file}"
            fi
            
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}警告: 无法下载配置文件 $file${NC}"
            fi
        fi
    done

    # 设置执行权限
    chmod +x "$CF_PATH"

    # 复制文件到安装目录
    cp "$CF_PATH" "$INSTALL_DIR/cf"
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$TMP_DIR/$file" ]; then
            cp "$TMP_DIR/$file" "$INSTALL_DIR/"
        fi
    done

    # 清理临时文件
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}Cloudflare 客户端已下载到 $INSTALL_DIR/cf${NC}"
    echo -e "${GREEN}配置文件已保存到 $INSTALL_DIR/目录${NC}"
}

# 检查客户端是否已安装
check_client_installed() {
    if [ ! -f "$INSTALL_DIR/cf" ]; then
        echo -e "${YELLOW}Cloudflare 客户端未安装，正在下载...${NC}"
        download_client
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    return 0
}

# 显示系统IP信息
show_ip_info() {
    echo -e "${BLUE}系统IP信息:${NC}"
    echo "----------------------------------------"
    
    # 显示主机名
    echo -e "${CYAN}主机名:${NC} $(hostname)"
    
    # 显示IPv4地址
    echo -e "${CYAN}IPv4地址:${NC}"
    if command -v ip &> /dev/null; then
        ip -4 addr | grep inet | grep -v "127.0.0.1"
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "inet addr:|inet " | grep -v "127.0.0.1"
    else
        echo "无法获取IPv4地址信息 (需要ip或ifconfig命令)"
    fi
    
    # 显示IPv6地址
    echo -e "${CYAN}IPv6地址:${NC}"
    if command -v ip &> /dev/null; then
        ip -6 addr | grep inet6 | grep -v "::1"
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "inet6 addr:|inet6 " | grep -v "::1"
    else
        echo "无法获取IPv6地址信息 (需要ip或ifconfig命令)"
    fi
    
    echo "----------------------------------------"
}

# 检查IPv6连接
check_ipv6_connectivity() {
    # 检查是否有IPv6地址
    local ipv6=$(get_local_ipv6)
    if [ "$ipv6" = "无IPv6地址" ]; then
        echo -e "${YELLOW}警告: 未检测到IPv6地址，IPv6优选可能无法正常工作${NC}"
        
        # 询问用户是否继续
        echo -n "是否仍然继续IPv6优选? [y/N] "
        read -r continue_ipv6
        
        if [[ ! "$continue_ipv6" =~ ^[Yy]$ ]]; then
            return 1
        fi
        return 0
    fi
    
    # 尝试使用ping6命令
    echo -e "${CYAN}尝试使用ping6连接到Google IPv6 DNS (2001:4860:4860::8888)...${NC}"
    if command -v ping6 &> /dev/null; then
        ping6 -c 3 2001:4860:4860::8888
        PING6_STATUS=$?
    else
        echo "ping6命令不可用，尝试使用ping -6"
        PING6_STATUS=1
    fi
    
    # 如果ping6失败，尝试使用ping命令
    if [ $PING6_STATUS -ne 0 ]; then
        echo -e "${CYAN}尝试使用ping连接到Google IPv6 DNS (2001:4860:4860::8888)...${NC}"
        ping -6 -c 3 2001:4860:4860::8888 2>/dev/null
        PING_STATUS=$?
        
        if [ $PING_STATUS -ne 0 ]; then
            echo -e "${YELLOW}警告: 无法连接到IPv6网络，IPv6优选可能无法正常工作${NC}"
            echo -e "${YELLOW}您的网络环境可能不支持IPv6，或者IPv6连接不稳定${NC}"
            
            # 询问用户是否继续
            echo -n "是否仍然继续IPv6优选? [y/N] "
            read -r continue_ipv6
            
            if [[ ! "$continue_ipv6" =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# 显示测速结果
display_results() {
    local result_file="$1"
    local ip_type="$2"
    
    if [ ! -f "$result_file" ]; then
        echo -e "${YELLOW}警告: 结果文件 $result_file 不存在${NC}"
        echo -e "${RED}未发现有效的${ip_type}地址，请检查您的网络连接或尝试其他优选选项${NC}"
        return 1
    fi
    
    # 检查文件是否为空
    if [ ! -s "$result_file" ]; then
        echo -e "${YELLOW}警告: 结果文件 $result_file 为空${NC}"
        echo -e "${RED}未发现有效的${ip_type}地址，请检查您的网络连接或尝试其他优选选项${NC}"
        return 1
    fi
    
    echo -e "${GREEN}$ip_type 优选结果:${NC}"
    echo "----------------------------------------"
    
    # 显示前10个结果
    head -n 10 "$result_file"
    
    echo "----------------------------------------"
    echo -e "${GREEN}结果已保存到 $result_file${NC}"
    
    # 复制最佳IP到当前目录
    if [ -f "$result_file" ] && [ -s "$result_file" ]; then
        # 提取第一行（最佳IP）
        BEST_IP=$(head -n 1 "$result_file" | cut -d ',' -f 1)
        if [ ! -z "$BEST_IP" ]; then
            echo "$BEST_IP" > "best_${ip_type,,}.txt"
            echo -e "${GREEN}最佳IP已保存到 best_${ip_type,,}.txt${NC}"
        fi
    fi
}

# IPv4优选
ipv4_optimize() {
    echo -e "${BLUE}开始IPv4优选...${NC}"
    
    # 检查客户端是否已安装
    check_client_installed
    if [ $? -ne 0 ]; then
        echo -e "${RED}客户端安装失败，无法进行优选。${NC}"
        return 1
    fi
    
    # 显示系统IP信息
    show_ip_info
    
    # 执行IPv4优选
    cd "$INSTALL_DIR"
    ./cf -ips 4 -outfile ipv4.csv
    
    # 检查优选是否成功
    if [ $? -ne 0 ]; then
        echo -e "${RED}IPv4优选失败，请检查网络连接或尝试其他选项。${NC}"
        echo
        echo "按任意键返回主菜单..."
        read -n 1
        return 1
    fi
    
    # 显示结果
    display_results "ipv4.csv" "IPv4"
    
    echo
    echo "按任意键返回主菜单..."
    read -n 1
}

# IPv6优选
ipv6_optimize() {
    echo -e "${BLUE}开始IPv6优选...${NC}"
    
    # 检查客户端是否已安装
    check_client_installed
    if [ $? -ne 0 ]; then
        echo -e "${RED}客户端安装失败，无法进行优选。${NC}"
        return 1
    fi
    
    # 检查IPv6连接
    check_ipv6_connectivity
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}已取消IPv6优选。${NC}"
        echo
        echo "按任意键返回主菜单..."
        read -n 1
        return 1
    fi
    
    # 执行IPv6优选
    cd "$INSTALL_DIR"
    ./cf -ips 6 -outfile ipv6.csv
    
    # 检查优选是否成功
    if [ $? -ne 0 ]; then
        echo -e "${RED}IPv6优选失败，请检查网络连接或尝试其他选项。${NC}"
        echo
        echo "按任意键返回主菜单..."
        read -n 1
        return 1
    fi
    
    # 显示结果
    display_results "ipv6.csv" "IPv6"
    
    echo
    echo "按任意键返回主菜单..."
    read -n 1
}

# 组合优选
combined_optimize() {
    echo -e "${BLUE}开始组合优选(IPv4+IPv6)...${NC}"
    
    # 检查客户端是否已安装
    check_client_installed
    if [ $? -ne 0 ]; then
        echo -e "${RED}客户端安装失败，无法进行优选。${NC}"
        return 1
    fi
    
    # 显示系统IP信息
    show_ip_info
    
    # 执行IPv4优选
    cd "$INSTALL_DIR"
    echo -e "${CYAN}正在优选IPv4地址...${NC}"
    ./cf -ips 4 -outfile ipv4.csv
    
    # 显示IPv4结果
    display_results "ipv4.csv" "IPv4"
    
    echo
    
    # 检查IPv6连接
    check_ipv6_connectivity
    if [ $? -eq 0 ]; then
        echo -e "${CYAN}正在优选IPv6地址...${NC}"
        ./cf -ips 6 -outfile ipv6.csv
        
        # 显示IPv6结果
        display_results "ipv6.csv" "IPv6"
    else
        echo -e "${YELLOW}已跳过IPv6优选。${NC}"
    fi
    
    echo -e "${GREEN}组合优选完成!${NC}"
    
    echo
    echo "按任意键返回主菜单..."
    read -n 1
}

# 主函数
main() {
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                ipv4_optimize
                ;;
            2)
                ipv6_optimize
                ;;
            3)
                combined_optimize
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

# 执行主函数
main
