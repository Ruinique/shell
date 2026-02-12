#!/bin/bash

# --- 阈值设定 ---
DIR_LIMIT_GB=10
FILE_LIMIT_GB=1

DIR_LIMIT_BYTES=$(( DIR_LIMIT_GB * 1024 * 1024 * 1024 ))
FILE_LIMIT_BYTES=$(( FILE_LIMIT_GB * 1024 * 1024 * 1024 ))

# 颜色定义
BOLD=$(tput bold); PURPLE=$(tput setaf 5); RED=$(tput setaf 1)
CYAN=$(tput setaf 6); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
BAR_COLOR=$(tput setaf 8) # 灰色作为进度条背景

# --- 进度条函数 ---
# 参数 $1: 字节数
draw_bar() {
    local bytes=$1
    local gb=$(( bytes / 1024 / 1024 / 1024 ))
    
    # 限制进度条最大长度为 20 个单位，防止超长
    local bar_len=$gb
    [[ $bar_len -gt 20 ]] && bar_len=20
    
    local bar=""
    for ((i=0; i<bar_len; i++)); do bar+="■"; done
    
    # 如果超过了 20GB，在末尾加个加号
    [[ $gb -gt 20 ]] && bar+="+"
    
    echo -n "${BAR_COLOR}[${bar}]${RESET}"
}

format_size() {
    numfmt --to=iec-i --suffix=B "$1"
}

scan_heavy_hitters() {
    local current_path="$1"
    local indent="$2"

    # 1. 扫描大文件 (>= 1G)
    find "$current_path" -maxdepth 1 -type f -size +"${FILE_LIMIT_GB}"G 2>/dev/null | while read -r file; do
        local f_size=$(stat -c%s "$file")
        printf "%-10s %s %s${PURPLE}%-10s${RESET} 📄 %s\n" \
               "" "$(draw_bar $f_size)" "$indent" "$(format_size $f_size)" "$(basename "$file")"
    done

    # 2. 扫描大文件夹 (>= 10G)
    find "$current_path" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r subdir; do
        local d_bytes=$(getfattr --absolute-names --only-values -n ceph.dir.rbytes "$subdir" 2>/dev/null)
        [[ -z "$d_bytes" ]] && d_bytes=0

        if [ "$d_bytes" -ge "$DIR_LIMIT_BYTES" ]; then
            printf "%-10s %s %s${RED}%-10s${RESET} ${BOLD}📁 %s/${RESET}\n" \
                   "" "$(draw_bar $d_bytes)" "$indent" "$(format_size $d_bytes)" "$(basename "$subdir")"
            
            scan_heavy_hitters "$subdir" "  $indent"
        fi
    done
}

# --- 主流程 ---
target_dir="${1:-.}"
abs_path=$(cd "$target_dir" && pwd)

echo -e "\n${BLUE}📊 Ceph 可视化空间扫描 (1GB/block)${RESET}"
echo -e "${CYAN}过滤规则: 文件夹 < ${DIR_LIMIT_GB}GB 不显示 | 文件 < ${FILE_LIMIT_GB}GB 不显示${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"

scan_heavy_hitters "$abs_path" ""

echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}扫描完成。${RESET}进度条中每个 ■ 代表约 1GB 占用。\n"
