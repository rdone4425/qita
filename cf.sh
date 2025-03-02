#!/bin/bash

# 检查是否有 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 清理屏幕
clear

# 删除 root 目录下的 cf.sh
rm -f /root/youxuan.sh >/dev/null 2>&1

# 设置变量
DOWNLOAD_DIR="/root/youxuan/download"  # 所有下载的文件都放在这个目录
RESULT_DIR="/root/youxuan/results"     # 测速结果放在这个目录

# 创建必要的目录
mkdir -p "${DOWNLOAD_DIR}" >/dev/null 2>&1
mkdir -p "${RESULT_DIR}" >/dev/null 2>&1

# 检测系统架构
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)  BINARY="amd64" ;;
    i386|i686)  BINARY="386" ;;
    aarch64)  BINARY="arm64" ;;
    armv7l|armv6l)  BINARY="arm" ;;
    mips64)  BINARY="mips64" ;;
    mips64le)  BINARY="mips64le" ;;
    mipsle)  BINARY="mipsle" ;;
    *)
        echo "不支持的系统架构: ${ARCH}"
        exit 1
        ;;
esac

# 配置文件路径 - 保持在父目录
CONFIG_FILE="/root/youxuan/config.json"
PROXY_LIST_FILE="/root/youxuan/proxy_list.conf"

# 默认代理 URL 列表
DEFAULT_PROXY_URLS=(
    "https://git.442595.xyz/proxy/"
    "https://mirror.ghproxy.com/"
    "https://ghproxy.com/"
)

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
{
    "current_proxy": 0,
    "proxy_urls": [
        "https://git.442595.xyz/proxy/",
        "https://mirror.ghproxy.com/",
        "https://ghproxy.com/"
    ],
    "selected_countries": [],
    "top_n_results": 5,
    "ports": [443, 2053, 2083, 2087, 2096, 8443],
    "gitlab": {
        "repo_url": "",
        "token": "",
        "branch": "main"
    }
}
EOF
    else
        # 如果配置文件存在但不包含必要字段，添加它们
        local temp_file=$(mktemp)
        
        if ! jq -e '.selected_countries' "$CONFIG_FILE" >/dev/null 2>&1; then
            jq '. + {"selected_countries": []}' "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
        fi
        
        if ! jq -e '.gitlab' "$CONFIG_FILE" >/dev/null 2>&1; then
            jq '. + {"gitlab": {"repo_url": "", "token": "", "branch": "main"}}' "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
        else
            if ! jq -e '.gitlab.repo_url' "$CONFIG_FILE" >/dev/null 2>&1; then
                jq '.gitlab.repo_url = ""' "$CONFIG_FILE" > "$temp_file"
                mv "$temp_file" "$CONFIG_FILE"
            fi
            
            if ! jq -e '.gitlab.branch' "$CONFIG_FILE" >/dev/null 2>&1; then
                jq '.gitlab.branch = "main"' "$CONFIG_FILE" > "$temp_file"
                mv "$temp_file" "$CONFIG_FILE"
            fi
        fi
    fi
}

# 获取所有代理 URL
get_proxy_urls() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        # 使用 jq 来正确解析 JSON 文件
        PROXY_URLS=($(jq -r '.proxy_urls[]' "$CONFIG_FILE"))
    else
        # 如果配置文件不存在或格式错误，使用默认值并重新初始化配置
        PROXY_URLS=("${DEFAULT_PROXY_URLS[@]}")
        init_config
    fi
}

# 获取当前代理 URL
get_current_proxy() {
    get_proxy_urls
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        local current_index=$(jq -r '.current_proxy' "$CONFIG_FILE")
        if [ -n "${PROXY_URLS[$current_index]}" ]; then
            echo "${PROXY_URLS[$current_index]}"
        else
            echo "${PROXY_URLS[0]}"
        fi
    else
        echo "${DEFAULT_PROXY_URLS[0]}"
    fi
}

# 添加新代理
add_proxy() {
    echo "请输入新的代理 URL（格式如 https://example.com/）："
    read -p "> " new_proxy
    
    # 验证 URL 格式
    if [[ ! "$new_proxy" =~ ^https?:// ]]; then
        echo "错误：无效的 URL 格式"
        return 1
    fi
    
    # 确保 URL 以 / 结尾
    [[ "$new_proxy" != */ ]] && new_proxy="${new_proxy}/"
    
    # 检查是否已存在
    get_proxy_urls
    for url in "${PROXY_URLS[@]}"; do
        if [ "$url" == "$new_proxy" ]; then
            echo "该代理 URL 已存在"
            return 1
        fi
    done
    
    # 添加新代理到配置文件
    local temp_file=$(mktemp)
    jq --arg url "$new_proxy" '.proxy_urls += [$url]' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
    echo "成功添加新代理 URL"
}

# 删除代理
delete_proxy() {
    get_proxy_urls
    echo "选择要删除的代理 URL："
    for i in "${!PROXY_URLS[@]}"; do
        echo "$((i+1)). ${PROXY_URLS[$i]}"
    done
    echo "0. 取消"
    
    read -p "请选择 [0-${#PROXY_URLS[@]}]: " del_choice
    
    if [[ "$del_choice" =~ ^[0-9]+$ ]] && [ "$del_choice" -ge 1 ] && [ "$del_choice" -le "${#PROXY_URLS[@]}" ]; then
        local current_index=$(jq -r '.current_proxy' "$CONFIG_FILE")
        local del_index=$((del_choice-1))
        
        # 更新配置文件
        local temp_file=$(mktemp)
        jq "del(.proxy_urls[$del_index])" "$CONFIG_FILE" > "$temp_file"
        
        # 如果删除的是当前使用的代理，重置为第一个代理
        if [ "$del_index" -eq "$current_index" ]; then
            jq '.current_proxy = 0' "$temp_file" > "$CONFIG_FILE"
        elif [ "$del_index" -lt "$current_index" ]; then
            # 如果删除的代理位于当前代理之前，更新索引
            jq ".current_proxy = $((current_index-1))" "$temp_file" > "$CONFIG_FILE"
        else
            mv "$temp_file" "$CONFIG_FILE"
        fi
        
        rm -f "$temp_file"
        echo "代理已删除"
    elif [ "$del_choice" != "0" ]; then
        echo "无效的选择"
    fi
}

# 切换代理 URL
switch_proxy() {
    clear
    echo "================================"
    echo "      代理服务器设置            "
    echo "================================"
    echo "当前代理: $(get_current_proxy)"
    echo
    get_proxy_urls
    if [ ${#PROXY_URLS[@]} -gt 0 ]; then
        echo "可用代理列表:"
        for i in "${!PROXY_URLS[@]}"; do
            echo "$((i+1)). ${PROXY_URLS[$i]}"
        done
    else
        echo "当前没有可用的代理"
    fi
    echo "--------------------------------"
    echo "a. 添加新代理"
    echo "d. 删除代理"
    echo "0. 返回主菜单"
    echo "================================"
    
    read -p "请选择 [0-${#PROXY_URLS[@]}/a/d]: " proxy_choice
    
    case $proxy_choice in
        [0-9]*)
            if [ "$proxy_choice" -ge 1 ] && [ "$proxy_choice" -le "${#PROXY_URLS[@]}" ]; then
                local temp_file=$(mktemp)
                jq ".current_proxy = $((proxy_choice-1))" "$CONFIG_FILE" > "$temp_file"
                mv "$temp_file" "$CONFIG_FILE"
                update_base_url
                echo "代理服务器已更新"
            elif [ "$proxy_choice" != "0" ]; then
                echo "无效的选择"
            fi
            ;;
        [aA])
            add_proxy
            ;;
        [dD])
            delete_proxy
            ;;
        *)
            echo "无效的选择"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 更新基础 URL
update_base_url() {
    PROXY_URL=$(get_current_proxy)
    BASE_URL="${PROXY_URL}https://raw.githubusercontent.com/rdone4425/qita/main/cf"
}

# 进度条函数
show_progress() {
    local prefix="$1"
    echo -n "${prefix} ["
    for ((i=0; i<25; i++)); do
        echo -n " "
    done
    echo -n "] 0%"
    
    local i=0
    while [ $i -le 25 ]; do
        echo -ne "\r${prefix} ["
        for ((j=0; j<i; j++)); do
            echo -n "="
        done
        for ((j=i; j<25; j++)); do
            echo -n " "
        done
        local percentage=$((i * 4))
        echo -n "] ${percentage}%"
        i=$((i + 1))
        sleep 0.1
    done
    echo
}

# 清理旧的测试结果
clean_old_results() {
    local prefix="$1"
    
    # 删除旧的 CSV 文件
    rm -f "${DOWNLOAD_DIR}/${prefix}.csv" >/dev/null 2>&1
    
    # 删除旧的国家结果文件
    local selected_countries=($(get_selected_countries))
    for country in "${selected_countries[@]}"; do
        rm -f "${DOWNLOAD_DIR}/${country}_${prefix}.txt" >/dev/null 2>&1
    done
}

# 下载文件
download_file() {
    local url="$1"
    local output_file="$2"
    local retry_count=3
    
    # 确保输出目录存在
    mkdir -p "$(dirname "$output_file")" >/dev/null 2>&1
    
    echo "正在下载: $url"
    echo "保存到: $output_file"
    
    # 尝试下载文件
    while [ $retry_count -gt 0 ]; do
        if curl -s -L --connect-timeout 10 --retry 3 "$url" -o "$output_file"; then
            echo "下载成功"
            return 0
        fi
        echo "下载失败，重试中..."
        retry_count=$((retry_count-1))
    done
    
    echo "下载失败，已达到最大重试次数"
    return 1
}

# 检查文件
check_files() {
    # 检查必要的文件是否存在
    if [ ! -f "${DOWNLOAD_DIR}/cf" ]; then
        echo "CF 程序不存在"
        return 1
    fi
    
    if [ ! -f "${DOWNLOAD_DIR}/ips-v4.txt" ]; then
        echo "IPv4 列表不存在"
        return 1
    fi
    
    if [ ! -f "${DOWNLOAD_DIR}/ips-v6.txt" ]; then
        echo "IPv6 列表不存在"
        return 1
    fi
    
    if [ ! -f "${DOWNLOAD_DIR}/locations.json" ]; then
        echo "位置信息不存在"
        return 1
    fi
    
    return 0
}

# 下载所有必要文件
download_all_files() {
    update_base_url
    local download_success=true
    
    # 创建目录
    echo "使用下载目录: ${DOWNLOAD_DIR}"
    if ! mkdir -p "${DOWNLOAD_DIR}"; then
        echo "错误: 无法创建下载目录"
        return 1
    fi
    
    # 下载文件
    echo "正在下载 CloudflareST..."
    download_file "${BASE_URL}/${BINARY}" "${DOWNLOAD_DIR}/cf" || download_success=false
    
    echo "正在下载 IP 列表..."
    download_file "${BASE_URL}/ips-v4.txt" "${DOWNLOAD_DIR}/ips-v4.txt" || download_success=false
    download_file "${BASE_URL}/ips-v6.txt" "${DOWNLOAD_DIR}/ips-v6.txt" || download_success=false
    
    echo "正在下载位置信息..."
    download_file "${BASE_URL}/locations.json" "${DOWNLOAD_DIR}/locations.json" || download_success=false
    
    if [ "$download_success" = false ]; then
        echo "错误: 部分文件下载失败"
        return 1
    fi
    
    # 设置执行权限
    chmod +x "${DOWNLOAD_DIR}/cf"
    
    # 验证文件权限
    if [ ! -x "${DOWNLOAD_DIR}/cf" ]; then
        echo "错误: 无法设置 CF 程序执行权限"
        return 1
    fi
    
    echo "所有文件下载完成，保存在: ${DOWNLOAD_DIR}"
    return 0
}

# 显示主菜单
show_menu() {
    clear
    echo "================================"
    echo "      CloudFlare IP 优选工具    "
    echo "================================"
    echo "1. IPv4 优选测速"
    echo "2. IPv6 优选测速"
    echo "3. IPv4+IPv6 优选测速"
    echo "4. 切换代理服务器"
    echo "5. 选择测试国家"
    echo "6. 设置优选数量"
    echo "7. 设置保存端口"
    echo "8. GitLab 设置"
    echo "0. 退出"
    echo "================================"
    echo -n "请输入你的选择 [0-8]: "
}

# 检查文件函数
check_file() {
    local file="$1"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        return 1
    fi
    return 0
}

# 获取当前选择的国家列表
get_selected_countries() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.selected_countries[]' "$CONFIG_FILE" 2>/dev/null
    fi
}

# 获取国家过滤器
get_country_filter() {
    local selected_countries=($(get_selected_countries))
    if [ ${#selected_countries[@]} -eq 0 ]; then
        return 1
    fi
    
    local filter=""
    for country in "${selected_countries[@]}"; do
        if [ -n "$filter" ]; then
            filter="${filter}|"
        fi
        filter="${filter}${country}"
    done
    
    echo "$filter"
    return 0
}

# 获取配置的端口列表
get_ports() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.ports[]' "$CONFIG_FILE"
    else
        echo "443"  # 默认只使用443端口
    fi
}

# 保存带端口的 IP 地址
save_ip_with_ports() {
    local ip_line="$1"
    local country="$2"  # 单个国家代码
    local ip=$(echo "$ip_line" | cut -d',' -f1)
    local ports=($(get_ports))
    local result=""
    
    for port in "${ports[@]}"; do
        if [[ "$ip" == *:* ]]; then
            # IPv6 地址
            result+="[${ip}]:${port}#${country}"
        else
            # IPv4 地址
            result+="${ip}:${port}#${country}"
        fi
        
        # 只在不是最后一个端口时添加换行符
        if [ "$port" != "${ports[-1]}" ]; then
            result+="\n"
        fi
    done
    
    echo -e "$result"
}

# 获取 GitLab 仓库 URL
get_gitlab_repo_url() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.gitlab.repo_url' "$CONFIG_FILE"
    else
        echo ""  # 默认为空
    fi
}

# 设置 GitLab 仓库 URL
set_gitlab_repo_url() {
    local url="$1"
    local temp_file=$(mktemp)
    jq --arg url "$url" '.gitlab.repo_url = $url' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 获取 GitLab Token
get_gitlab_token() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.gitlab.token' "$CONFIG_FILE"
    else
        echo ""  # 默认为空
    fi
}

# 设置 GitLab Token
set_gitlab_token() {
    local token="$1"
    local temp_file=$(mktemp)
    jq --arg token "$token" '.gitlab.token = $token' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 获取 GitLab 分支
get_gitlab_branch() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.gitlab.branch' "$CONFIG_FILE"
    else
        echo "main"  # 默认值
    fi
}

# 设置 GitLab 分支
set_gitlab_branch() {
    local branch="$1"
    local temp_file=$(mktemp)
    jq --arg branch "$branch" '.gitlab.branch = $branch' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 获取 GitLab 项目 ID
get_gitlab_project_id() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.gitlab.project_id' "$CONFIG_FILE"
    else
        echo ""  # 默认为空
    fi
}

# 设置 GitLab 项目 ID
set_gitlab_project_id() {
    local id="$1"
    local temp_file=$(mktemp)
    jq --arg id "$id" '.gitlab.project_id = $id' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 检查 GitLab 配置是否完整
is_gitlab_configured() {
    local repo_url=$(get_gitlab_repo_url)
    local token=$(get_gitlab_token)
    local project_id=$(get_gitlab_project_id)
    
    if [ -n "$repo_url" ] && [ -n "$token" ] && [ -n "$project_id" ]; then
        return 0  # 配置完整
    else
        return 1  # 配置不完整
    fi
}

# 合并所有国家的结果文件
merge_result_files() {
    local ip_type="$1"  # ipv4 或 ipv6 或 all
    local output_file="${RESULT_DIR}/merged_${ip_type}.txt"
    local selected_countries=($(get_selected_countries))
    
    echo "正在合并所有国家的结果文件..."
    
    # 清空输出文件
    > "$output_file"
    
    # 合并所有国家的文件
    if [ "$ip_type" = "all" ]; then
        # 合并 IPv4 和 IPv6 的结果
        for country in "${selected_countries[@]}"; do
            if [ -f "${RESULT_DIR}/${country}_ipv4.txt" ]; then
                cat "${RESULT_DIR}/${country}_ipv4.txt" >> "$output_file"
                # 删除单独的国家文件
                rm -f "${RESULT_DIR}/${country}_ipv4.txt"
            fi
            if [ -f "${RESULT_DIR}/${country}_ipv6.txt" ]; then
                cat "${RESULT_DIR}/${country}_ipv6.txt" >> "$output_file"
                # 删除单独的国家文件
                rm -f "${RESULT_DIR}/${country}_ipv6.txt"
            fi
        done
    else
        # 只合并指定类型的结果
        for country in "${selected_countries[@]}"; do
            if [ -f "${RESULT_DIR}/${country}_${ip_type}.txt" ]; then
                cat "${RESULT_DIR}/${country}_${ip_type}.txt" >> "$output_file"
                # 删除单独的国家文件
                rm -f "${RESULT_DIR}/${country}_${ip_type}.txt"
            fi
        done
    fi
    
    # 检查合并后的文件是否为空
    if [ -s "$output_file" ]; then
        echo "所有结果已合并到: $output_file"
        echo "单独的国家文件已删除"
        echo "合并后的文件内容:"
        cat "$output_file"
        
        # 上传到 GitLab
        if is_gitlab_configured; then
            echo "正在将合并后的文件上传到 GitLab..."
            if upload_to_gitlab "$output_file"; then
                echo "文件已成功上传到 GitLab"
            else
                echo "上传到 GitLab 失败"
            fi
        else
            echo "GitLab 未配置，跳过上传"
        fi
    else
        echo "没有找到可合并的结果文件"
        rm -f "$output_file"  # 删除空文件
    fi
}

# 上传到 GitLab
upload_to_gitlab() {
    local file="$1"
    local repo_url=$(get_gitlab_repo_url)
    local token=$(get_gitlab_token)
    local branch=$(get_gitlab_branch)
    local project_id=$(get_gitlab_project_id)
    
    if [ -z "$repo_url" ] || [ -z "$token" ] || [ -z "$project_id" ]; then
        echo "GitLab 配置不完整，无法上传"
        return 1
    fi
    
    local filename=$(basename "$file")
    local content=$(cat "$file")
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local commit_message="Update IP list - $timestamp"
    
    echo "正在上传到 GitLab 仓库..."
    echo "仓库URL: $repo_url"
    echo "项目ID: $project_id"
    echo "分支: $branch"
    echo "文件名: $filename"
    
    # 构建 API URL
    local gitlab_domain=$(echo "$repo_url" | cut -d'/' -f3)
    local api_url="https://${gitlab_domain}/api/v4/projects"
    
    # 检查文件是否存在
    local file_exists=$(curl -s --header "PRIVATE-TOKEN: $token" \
        "${api_url}/${project_id}/repository/files/${filename}?ref=${branch}" \
        | jq -r '.message // empty')
    
    # 准备 JSON 数据，正确处理内容中的特殊字符
    local json_data=$(jq -n \
        --arg branch "$branch" \
        --arg content "$content" \
        --arg message "$commit_message" \
        '{"branch": $branch, "content": $content, "commit_message": $message}')
    
    if [[ "$file_exists" == *"404 File Not Found"* ]] || [[ "$file_exists" == *"doesn't exist"* ]]; then
        # 文件不存在，创建它
        echo "文件不存在，创建新文件..."
        curl -s --request POST --header "PRIVATE-TOKEN: $token" \
            --header "Content-Type: application/json" \
            --data "$json_data" \
            "${api_url}/${project_id}/repository/files/${filename}"
        
        local status=$?
        if [ $status -ne 0 ]; then
            echo "错误: 文件创建失败 (状态码: $status)"
            return 1
        fi
    else
        # 文件存在，更新它
        echo "文件已存在，更新文件..."
        curl -s --request PUT --header "PRIVATE-TOKEN: $token" \
            --header "Content-Type: application/json" \
            --data "$json_data" \
            "${api_url}/${project_id}/repository/files/${filename}"
        
        local status=$?
        if [ $status -ne 0 ]; then
            echo "错误: 文件更新失败 (状态码: $status)"
            return 1
        fi
    fi
    
    echo "上传完成"
    return 0
}

# 设置 GitLab 菜单
set_gitlab_menu() {
    clear
    echo "================================"
    echo "      GitLab 设置               "
    echo "================================"
    echo "当前 GitLab 配置:"
    echo "仓库 URL: $(get_gitlab_repo_url)"
    echo "项目 ID: $(get_gitlab_project_id)"
    echo "Token: $(if [ -n "$(get_gitlab_token)" ]; then echo "已设置"; else echo "未设置"; fi)"
    echo "分支: $(get_gitlab_branch)"
    echo
    echo "1. 设置仓库 URL"
    echo "2. 设置项目 ID"
    echo "3. 设置 Token"
    echo "4. 设置分支"
    echo "5. 测试连接"
    echo "0. 返回主菜单"
    echo "================================"
    
    read -p "请选择 [0-5]: " gitlab_choice
    
    case $gitlab_choice in
        1)
            read -p "请输入 GitLab 仓库 URL (例如 https://gitlab.com): " repo_url
            set_gitlab_repo_url "$repo_url"
            echo "仓库 URL 已更新"
            ;;
        2)
            read -p "请输入 GitLab 项目 ID: " project_id
            set_gitlab_project_id "$project_id"
            echo "项目 ID 已更新"
            ;;
        3)
            read -p "请输入 GitLab 访问令牌: " token
            set_gitlab_token "$token"
            echo "Token 已更新"
            ;;
        4)
            read -p "请输入分支名称 [默认: main]: " branch
            branch=${branch:-main}
            set_gitlab_branch "$branch"
            echo "分支已更新"
            ;;
        5)
            test_gitlab_connection
            ;;
        0)
            return 0
            ;;
        *)
            echo "无效的选择"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 测试 GitLab 连接
test_gitlab_connection() {
    local repo_url=$(get_gitlab_repo_url)
    local token=$(get_gitlab_token)
    local project_id=$(get_gitlab_project_id)
    
    if [ -z "$repo_url" ] || [ -z "$token" ] || [ -z "$project_id" ]; then
        echo "GitLab 配置不完整，请先完成配置"
        return 1
    fi
    
    echo "正在测试 GitLab 连接..."
    
    # 构建 API URL
    local api_url="${repo_url}/api/v4/projects/${project_id}"
    
    # 发送请求
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --header "PRIVATE-TOKEN: $token" \
        "${api_url}")
    
    # 检查响应
    if [ "$http_code" -eq 200 ]; then
        echo "连接成功！GitLab 配置有效"
        return 0
    else
        echo "连接失败，HTTP 状态码: $http_code"
        echo "请检查您的 GitLab 配置"
        return 1
    fi
}

# 处理测速结果
process_test_results() {
    local ip_type="$1"
    local result_file="${DOWNLOAD_DIR}/${ip_type}.csv"
    local selected_countries=($(get_selected_countries))
    local top_n=$(get_top_n_results)
    local locations_file="${DOWNLOAD_DIR}/locations.json"
    
    echo "正在处理测速结果..."
    
    # 如果没有选择国家，使用所有结果
    if [ ${#selected_countries[@]} -eq 0 ]; then
        echo "未选择特定国家，使用所有测速结果"
        return 0
    fi
    
    # 检查 locations.json 文件
    if [ ! -f "$locations_file" ]; then
        echo "错误: locations.json 文件不存在于 ${locations_file}"
        echo "尝试重新下载..."
        download_file "${BASE_URL}/locations.json" "$locations_file"
    fi
    
    echo "使用位置文件: $locations_file"
    
    # 确保结果目录存在
    mkdir -p "${RESULT_DIR}" >/dev/null 2>&1
    
    # 过滤结果
    if [ -f "${result_file}" ]; then
        # 显示CSV文件的前几行，用于调试
        echo "CSV文件内容示例:"
        head -n 3 "${result_file}"
        
        # 获取所有选中的国家
        for country in "${selected_countries[@]}"; do
            # 尝试获取国家名称
            local country_name=""
            if [ -f "$locations_file" ]; then
                # 尝试不同的 JSON 路径，并只取第一行结果
                country_name=$(jq -r --arg code "$country" '.[] | select(.cca2==$code) | .country' "$locations_file" 2>/dev/null | head -n 1)
                
                if [ -z "$country_name" ] || [ "$country_name" == "null" ]; then
                    country_name=$(jq -r --arg code "$country" '.[] | select(.code==$code) | .name' "$locations_file" 2>/dev/null | head -n 1)
                fi
                
                if [ -z "$country_name" ] || [ "$country_name" == "null" ]; then
                    country_name=$(jq -r --arg code "$country" '.[$code] | .name' "$locations_file" 2>/dev/null | head -n 1)
                fi
            fi
            
            # 如果仍然没有找到国家名称，使用国家代码
            if [ -z "$country_name" ] || [ "$country_name" == "null" ]; then
                country_name="$country"
            fi
            
            echo "== $country ($country_name) =="
            
            # 直接从CSV文件中提取匹配的行
            local ip_list=$(grep -i "$country" "${result_file}" | sort -t ',' -k3,3n | head -n "$top_n" | cut -d ',' -f1)
            
            if [ -n "$ip_list" ]; then
                # 将结果保存到 RESULT_DIR 目录，添加端口和国家标记
                local country_file="${RESULT_DIR}/${country}_${ip_type}.txt"
                > "$country_file"  # 清空文件
                
                while IFS= read -r ip; do
                    local ports=($(get_ports))
                    for port in "${ports[@]}"; do
                        if [[ "$ip" == *:* ]]; then
                            # IPv6 地址
                            echo "[${ip}]:${port}#${country}" >> "$country_file"
                        else
                            # IPv4 地址
                            echo "${ip}:${port}#${country}" >> "$country_file"
                        fi
                    done
                done <<< "$ip_list"
                
                echo "IP 列表已保存到: $country_file"
                
                # 显示结果（仅显示第一个端口的结果）
                local display_list=""
                while IFS= read -r ip; do
                    local port="${ports[0]}"
                    if [[ "$ip" == *:* ]]; then
                        # IPv6 地址
                        display_list+="[${ip}]:${port}#${country}\n"
                    else
                        # IPv4 地址
                        display_list+="${ip}:${port}#${country}\n"
                    fi
                done <<< "$ip_list"
                echo -e "$display_list"
            else
                echo "没有找到可用的 IP 地址"
            fi
            echo "----------------------------------------"
        done
    else
        echo "结果文件不存在: ${result_file}"
    fi
}

# 修改 run_ip_test 函数，添加合并功能
run_ip_test() {
    local ip_version="$1"  # 4 或 6
    local top_n=$(get_top_n_results)
    local result_file="${DOWNLOAD_DIR}/ipv${ip_version}.csv"
    
    # 清理旧文件
    clean_old_results "ipv${ip_version}"
    
    if ! check_files; then
        echo "正在下载所需文件..."
        if ! download_all_files; then
            echo "文件下载失败，无法继续测速"
            return 1
        fi
    fi
    
    if [ -x "${DOWNLOAD_DIR}/cf" ]; then
        cd "${DOWNLOAD_DIR}"
        
        # 检查是否有选择的国家
        local selected_countries=($(get_selected_countries))
        if [ ${#selected_countries[@]} -eq 0 ]; then
            echo "请先选择测试国家（菜单选项5）"
            return 1
        fi
        
        echo "开始测试 IPv${ip_version} 地址..."
        
        # 运行测速程序，将结果保存在下载目录
        ./cf -ips "${ip_version}" -outfile "${result_file}"
        
        # 处理测速结果
        process_test_results "ipv${ip_version}"
        
        # 合并结果文件
        merge_result_files "ipv${ip_version}"
        
        echo "IPv${ip_version} 测速完成"
    else
        echo "错误: CF 程序不存在或没有执行权限"
        return 1
    fi
}

# 修改 run_both_test 函数，添加合并功能
run_both_test() {
    local top_n=$(get_top_n_results)
    
    # 清理旧文件
    clean_old_results "ipv4"
    clean_old_results "ipv6"
    
    if ! check_files; then
        echo "正在下载所需文件..."
        if ! download_all_files; then
            echo "文件下载失败，无法继续测速"
            return 1
        fi
    fi
    
    if [ -x "${DOWNLOAD_DIR}/cf" ]; then
        cd "${DOWNLOAD_DIR}"
        
        # 检查是否有选择的国家
        local selected_countries=($(get_selected_countries))
        if [ ${#selected_countries[@]} -eq 0 ]; then
            echo "请先选择测试国家（菜单选项5）"
            return 1
        fi
        
        # 创建结果目录
        mkdir -p "${RESULT_DIR}"
        
        # 运行 IPv4 测速
        echo "运行 IPv4 测速..."
        ./cf -ips 4 -outfile ipv4.csv
        echo "----------------------------------------"
        echo "IPv4 测速结果 (每个国家延迟前 ${top_n})："
        echo "----------------------------------------"
        
        # 处理 IPv4 测速结果
        process_test_results "ipv4"
        
        # 运行 IPv6 测速
        echo "运行 IPv6 测速..."
        ./cf -ips 6 -outfile ipv6.csv
        echo "----------------------------------------"
        echo "IPv6 测速结果 (每个国家延迟前 ${top_n})："
        echo "----------------------------------------"
        
        # 处理 IPv6 测速结果
        process_test_results "ipv6"
        
        # 合并所有结果文件
        merge_result_files "all"
        
        echo "所有国家的IP列表已保存到: ${RESULT_DIR}/"
    else
        echo "错误: CF 程序不存在或没有执行权限"
        return 1
    fi
}

# 获取当前选择的城市列表
get_selected_cities() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.selected_cities[]' "$CONFIG_FILE" 2>/dev/null
    fi
}

# 更新选中的城市
update_selected_cities() {
    local cities=("$@")
    local json_array=$(printf '%s\n' "${cities[@]}" | jq -R . | jq -s .)
    local temp_file=$(mktemp)
    jq --argjson cities "$json_array" '.selected_cities = $cities' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 获取每个城市显示的IP数量
get_top_n_results() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.top_n_results' "$CONFIG_FILE"
    else
        echo "5"  # 默认值
    fi
}

# 设置每个城市显示的IP数量
set_top_n_results() {
    local n="$1"
    local temp_file=$(mktemp)
    jq --arg n "$n" '.top_n_results = ($n|tonumber)' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 添加设置优选数量的菜单
set_top_n_menu() {
    clear
    echo "================================"
    echo "      优选数量设置              "
    echo "================================"
    echo "当前每个城市显示IP数量: $(get_top_n_results)"
    echo
    read -p "请输入新的数量 (1-20): " new_n
    
    if [[ "$new_n" =~ ^[0-9]+$ ]] && [ "$new_n" -ge 1 ] && [ "$new_n" -le 20 ]; then
        set_top_n_results "$new_n"
        echo "设置已更新"
    else
        echo "无效的输入，请输入1-20之间的数字"
    fi
    
    read -p "按回车键继续..."
}

# 从 locations.json 获取国家代码
get_country_code() {
    local airport_code="$1"
    local locations_file="${DOWNLOAD_DIR}/locations.json"
    
    # 检查 locations.json 是否存在
    if [ -f "$locations_file" ]; then
        local country=$(jq -r --arg code "$airport_code" '.[] | select(.iata==$code) | .cca2' "$locations_file")
        if [ -n "$country" ] && [ "$country" != "null" ]; then
            echo "$country"
            return
        fi
    fi
    
    echo "$airport_code"  # 如果找不到对应的国家代码，返回原始代码
}

# 处理 IP:端口 列表，添加国家代码
process_ip_port_list() {
    local input_file="$1"
    local output_file="$2"
    
    # 确保输出目录存在
    mkdir -p "$(dirname "$output_file")"
    
    # 清空输出文件
    > "$output_file"
    
    # 获取所有选中的国家
    local selected_countries=($(get_selected_countries))
    
    # 逐行处理输入文件
    while IFS= read -r line; do
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        # 提取 IP 和端口
        if [[ "$line" =~ ([^:]+):([0-9]+) ]]; then
            local ip_part="${BASH_REMATCH[1]}"
            local port="${BASH_REMATCH[2]}"
            
            # 从文件名中提取国家代码
            local country=""
            local filename=$(basename "$input_file")
            
            # 如果文件名包含国家代码（例如 US_ipv4.txt），则提取它
            if [[ "$filename" =~ ^([A-Z]{2})_ ]]; then
                country="${BASH_REMATCH[1]}"
            else
                # 尝试从目录结构中查找国家代码
                for country_code in "${selected_countries[@]}"; do
                    if grep -q "$country_code" <<< "$input_file"; then
                        country="$country_code"
                        break
                    fi
                done
                
                # 如果仍然没有找到国家代码，使用默认值
                if [ -z "$country" ]; then
                    country="Unknown"
                fi
            fi
            
            # 输出格式化的行
            if [[ "$ip_part" == *:* ]]; then
                # IPv6 地址 - 确保只有一对方括号
                if [[ "$ip_part" == \[*\] ]]; then
                    # 已经有方括号，直接使用
                    echo "${ip_part}:${port}#${country}" >> "$output_file"
                else
                    # 添加方括号
                    echo "[${ip_part}]:${port}#${country}" >> "$output_file"
                fi
            else
                # IPv4 地址
                echo "${ip_part}:${port}#${country}" >> "$output_file"
            fi
        fi
    done < "$input_file"
}

# 添加自动模式函数
run_auto_mode() {
    local test_type="${1:-both}"  # 默认为 both
    
    echo "开始自动测速，类型: $test_type..."
    
    # 检查文件
    if ! check_files; then
        echo "正在下载所需文件..."
        if ! download_all_files; then
            echo "文件下载失败，无法继续测速"
            return 1
        fi
    fi
    
    # 根据测试类型运行相应的测速
    case "$test_type" in
        ipv4)
            echo "运行 IPv4 测速..."
            run_ip_test 4
            # 合并 IPv4 结果文件
            merge_result_files "ipv4"
            ;;
        ipv6)
            echo "运行 IPv6 测速..."
            run_ip_test 6
            # 合并 IPv6 结果文件
            merge_result_files "ipv6"
            ;;
        both|*)
            echo "运行双栈测速..."
            run_both_test
            # 合并所有结果文件
            merge_result_files "all"
            ;;
    esac
    
    echo "自动测速完成"
}

# 主函数
main() {
    # 初始化配置
    init_config
    update_base_url
    
    # 检查是否为自动模式
    if [[ "$1" == "auto"* ]]; then
        # 自动模式
        local test_type="both"
        
        # 检查是否指定了测试类型
        if [ "$1" = "auto-ipv4" ]; then
            test_type="ipv4"
        elif [ "$1" = "auto-ipv6" ]; then
            test_type="ipv6"
        fi
        
        run_auto_mode "$test_type"
        exit 0
    else
        # 交互模式
        while true; do
            show_menu
            read choice
            case $choice in
                1)
                    run_ipv4_test
                    echo
                    read -p "按回车键继续..."
                    clear
                    ;;
                2)
                    run_ipv6_test
                    echo
                    read -p "按回车键继续..."
                    clear
                    ;;
                3)
                    run_both_test
                    echo
                    read -p "按回车键继续..."
                    clear
                    ;;
                4)
                    switch_proxy
                    clear
                    ;;
                5)
                    select_countries
                    clear
                    ;;
                6)
                    set_top_n_menu
                    clear
                    ;;
                7)
                    set_ports_menu
                    clear
                    ;;
                8)
                    set_gitlab_menu
                    clear
                    ;;
                0)
                    echo "退出程序"
                    exit 0
                    ;;
                *)
                    echo "无效的选择，请重试"
                    echo
                    read -p "按回车键继续..."
                    clear
                    ;;
            esac
        done
    fi
}

# 执行主函数
main "$@"

# 获取配置的端口列表
get_ports() {
    if [ -f "$CONFIG_FILE" ] && jq -e . >/dev/null 2>&1 < "$CONFIG_FILE"; then
        jq -r '.ports[]' "$CONFIG_FILE"
    else
        echo "443"  # 默认只使用443端口
    fi
}

# 设置端口菜单
set_ports_menu() {
    clear
    echo "================================"
    echo "      端口设置                  "
    echo "================================"
    echo "当前端口列表:"
    get_ports | tr '\n' ' '
    echo
    echo
    echo "1. 添加端口"
    echo "2. 删除端口"
    echo "3. 恢复默认端口"
    echo "0. 返回主菜单"
    echo "================================"
    
    read -p "请选择 [0-3]: " port_choice
    
    case $port_choice in
        1)
            read -p "请输入要添加的端口 (1-65535): " new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                add_port "$new_port"
                echo "端口已添加"
            else
                echo "无效的端口号"
            fi
            ;;
        2)
            delete_port
            ;;
        3)
            reset_ports
            echo "已恢复默认端口"
            ;;
        0)
            return 0
            ;;
        *)
            echo "无效的选择"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 添加端口
add_port() {
    local new_port="$1"
    local current_ports=($(get_ports))
    
    # 检查端口是否已存在
    for port in "${current_ports[@]}"; do
        if [ "$port" -eq "$new_port" ]; then
            echo "端口已存在"
            return 1
        fi
    done
    
    # 添加新端口
    current_ports+=("$new_port")
    update_ports "${current_ports[@]}"
}

# 删除端口
delete_port() {
    local current_ports=($(get_ports))
    
    echo "选择要删除的端口:"
    for i in "${!current_ports[@]}"; do
        echo "$((i+1)). ${current_ports[$i]}"
    done
    echo "0. 取消"
    
    read -p "请选择 [0-${#current_ports[@]}]: " del_choice
    
    if [[ "$del_choice" =~ ^[0-9]+$ ]] && [ "$del_choice" -ge 1 ] && [ "$del_choice" -le "${#current_ports[@]}" ]; then
        local del_index=$((del_choice-1))
        unset current_ports[$del_index]
        update_ports "${current_ports[@]}"
        echo "端口已删除"
    elif [ "$del_choice" != "0" ]; then
        echo "无效的选择"
    fi
}

# 重置端口为默认值
reset_ports() {
    local default_ports=(443 2053 2083 2087 2096 8443)
    update_ports "${default_ports[@]}"
}

# 更新端口列表
update_ports() {
    local ports=("$@")
    local json_array=$(printf '%s\n' "${ports[@]}" | jq -R . | jq -s .)
    local temp_file=$(mktemp)
    jq --argjson ports "$json_array" '.ports = $ports' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# 选择测试国家
select_countries() {
    clear
    echo "================================"
    echo "      选择测试国家              "
    echo "================================"
    
    # 获取当前选择的国家
    local selected_countries=($(get_selected_countries))
    
    echo "当前选择的国家: ${selected_countries[*]:-无}"
    echo
    
    # 检查 locations.json 文件
    local locations_file="${DOWNLOAD_DIR}/locations.json"
    if [ ! -f "$locations_file" ]; then
        echo "正在下载位置信息..."
        update_base_url
        download_file "${BASE_URL}/locations.json" "$locations_file"
    fi
    
    if [ ! -f "$locations_file" ]; then
        echo "错误: 无法获取位置信息"
        read -p "按回车键继续..."
        return 1
    fi
    
    # 获取可用的国家列表
    echo "可用的国家列表:"
    local countries=($(jq -r '.[] | .cca2' "$locations_file" 2>/dev/null | sort -u))
    
    if [ ${#countries[@]} -eq 0 ]; then
        # 尝试其他可能的 JSON 路径
        countries=($(jq -r '.[] | .code' "$locations_file" 2>/dev/null | sort -u))
    fi
    
    if [ ${#countries[@]} -eq 0 ]; then
        echo "错误: 无法从位置文件中提取国家代码"
        read -p "按回车键继续..."
        return 1
    fi
    
    # 显示国家列表
    local count=0
    for country in "${countries[@]}"; do
        # 获取国家名称
        local country_name=$(jq -r --arg code "$country" '.[] | select(.cca2==$code) | .country' "$locations_file" 2>/dev/null | head -n 1)
        
        if [ -z "$country_name" ] || [ "$country_name" == "null" ]; then
            country_name=$(jq -r --arg code "$country" '.[] | select(.code==$code) | .name' "$locations_file" 2>/dev/null | head -n 1)
        fi
        
        if [ -z "$country_name" ] || [ "$country_name" == "null" ]; then
            country_name="$country"
        fi
        
        # 检查是否已选择
        local selected=""
        for sel in "${selected_countries[@]}"; do
            if [ "$sel" == "$country" ]; then
                selected="[已选]"
                break
            fi
        done
        
        printf "%3d. %-5s %-20s %s\n" $((count+1)) "$country" "$country_name" "$selected"
        count=$((count+1))
        
        # 每20个国家暂停一次
        if [ $((count % 20)) -eq 0 ]; then
            echo
            read -p "按回车键查看更多国家，输入q退出..." key
            if [ "$key" == "q" ] || [ "$key" == "Q" ]; then
                break
            fi
            echo
        fi
    done
    
    echo
    echo "操作选项:"
    echo "a. 添加国家"
    echo "r. 移除国家"
    echo "c. 清除所有选择"
    echo "0. 返回主菜单"
    echo "================================"
    
    read -p "请选择操作 [a/r/c/0]: " op_choice
    
    case $op_choice in
        [aA])
            read -p "请输入要添加的国家代码 (例如 US,JP,HK): " add_countries
            IFS=',' read -ra add_array <<< "$add_countries"
            for country in "${add_array[@]}"; do
                # 检查是否是有效的国家代码
                if grep -q "^${country}$" <(printf '%s\n' "${countries[@]}"); then
                    # 检查是否已经选择
                    local already_selected=false
                    for sel in "${selected_countries[@]}"; do
                        if [ "$sel" == "$country" ]; then
                            already_selected=true
                            break
                        fi
                    done
                    
                    if [ "$already_selected" = false ]; then
                        selected_countries+=("$country")
                    fi
                else
                    echo "警告: $country 不是有效的国家代码"
                fi
            done
            
            # 更新配置
            local json_array=$(printf '%s\n' "${selected_countries[@]}" | jq -R . | jq -s .)
            local temp_file=$(mktemp)
            jq --argjson countries "$json_array" '.selected_countries = $countries' "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
            echo "国家已添加"
            ;;
        [rR])
            if [ ${#selected_countries[@]} -eq 0 ]; then
                echo "当前没有选择的国家"
            else
                echo "当前选择的国家:"
                for i in "${!selected_countries[@]}"; do
                    echo "$((i+1)). ${selected_countries[$i]}"
                done
                
                read -p "请输入要移除的国家编号 (例如 1,3,5): " remove_indices
                IFS=',' read -ra remove_array <<< "$remove_indices"
                
                # 从大到小排序，以便正确删除
                IFS=$'\n' remove_array=($(sort -nr <<<"${remove_array[*]}"))
                
                for idx in "${remove_array[@]}"; do
                    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#selected_countries[@]}" ]; then
                        unset 'selected_countries[idx-1]'
                    fi
                done
                
                # 重新索引数组
                selected_countries=("${selected_countries[@]}")
                
                # 更新配置
                local json_array=$(printf '%s\n' "${selected_countries[@]}" | jq -R . | jq -s .)
                local temp_file=$(mktemp)
                jq --argjson countries "$json_array" '.selected_countries = $countries' "$CONFIG_FILE" > "$temp_file"
                mv "$temp_file" "$CONFIG_FILE"
                echo "国家已移除"
            fi
            ;;
        [cC])
            # 清除所有选择
            local temp_file=$(mktemp)
            jq '.selected_countries = []' "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
            echo "所有国家选择已清除"
            ;;
        0)
            return 0
            ;;
        *)
            echo "无效的选择"
            ;;
    esac
    
    read -p "按回车键继续..."
}
