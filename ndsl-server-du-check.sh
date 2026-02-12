#!/bin/bash

# --- 阈值设定 ---
DIR_LIMIT_GB=100
FILE_LIMIT_GB=1

DIR_LIMIT_BYTES=$(( DIR_LIMIT_GB * 1024 * 1024 * 1024 ))
FILE_LIMIT_BYTES=$(( FILE_LIMIT_GB * 1024 * 1024 * 1024 ))

# 颜色定义
BOLD=$(tput bold); PURPLE=$(tput setaf 5); RED=$(tput setaf 1)
CYAN=$(tput setaf 6); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
BAR_COLOR=$(tput setaf 8) # 灰色作为进度条

# --- 进度条函数 ---
draw_bar() {
    local bytes=$1
    local gb=$(( bytes / 1024 / 1024 / 1024 ))
    local bar_len=$gb
    [[ $bar_len -gt 20 ]] && bar_len=20
    local bar=""
    for ((i=0; i<bar_len; i++)); do bar+="■"; done
    [[ $gb -gt 20 ]] && bar+="+"
    echo -n "${BAR_COLOR}[${bar}]${RESET}"
}

format_size() {
    numfmt --to=iec-i --suffix=B "$1"
}

scan_heavy_hitters() {
    local current_path="$1"
    # 确保传入的是绝对路径
    local abs_current=$(realpath "$current_path")

    # 1. 扫描大文件 (使用绝对路径)
    # 使用 -printf 直接输出大小和路径，避免 basename 丢失位置
    find "$abs_current" -maxdepth 1 -type f -size +"${FILE_LIMIT_GB}"G 2>/dev/null | while read -r file; do
        local f_size=$(stat -c%s "$file")
        printf "%-10s %s ${PURPLE}%-10s${RESET} 📄 %s\n" \
               "" "$(draw_bar $f_size)" "$(format_size $f_size)" "$file"
    done

    # 2. 扫描大文件夹 (使用绝对路径)
    find "$abs_current" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r subdir; do
        local abs_subdir=$(realpath "$subdir")
        # 直接通过 getfattr 获取 Ceph 递归大小
        local d_bytes=$(getfattr --absolute-names --only-values -n ceph.dir.rbytes "$abs_subdir" 2>/dev/null)
        [[ -z "$d_bytes" ]] && d_bytes=0

        if [ "$d_bytes" -ge "$DIR_LIMIT_BYTES" ]; then
            printf "%-10s %s ${RED}%-10s${RESET} ${BOLD}📁 %s/${RESET}\n" \
                   "" "$(draw_bar $d_bytes)" "$(format_size $d_bytes)" "$abs_subdir"
            
            # 递归扫描
            scan_heavy_hitters "$abs_subdir"
        fi
    done
}

# --- 主流程 ---
target_dir="${1:-.}"
# 预先检查路径是否存在
if [ ! -d "$target_dir" ]; then
    echo "${RED}错误: 目录 $target_dir 不存在${RESET}"
    exit 1
fi

abs_root=$(realpath "$target_dir")

echo -e "\n${BLUE}📊 Ceph 绝对路径空间扫描 (1GB/block)${RESET}"
echo -e "${CYAN}起始路径: $abs_root${RESET}"
echo -e "${CYAN}过滤规则: 文件夹 < ${DIR_LIMIT_GB}GB | 文件 < ${FILE_LIMIT_GB}GB 不显示${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"

scan_heavy_hitters "$abs_root"

echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}扫描完成。${RESET}\n"
