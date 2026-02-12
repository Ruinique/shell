#!/bin/bash

# --- 动态阈值与配置 (优先读取环境变量) ---
# 文件夹阈值，默认 100GB
DIR_LIMIT_GB=${DIR_LIMIT_GB:-100}
# 文件阈值，默认 1GB
FILE_LIMIT_GB=${FILE_LIMIT_GB:-1}
# 排除前缀，多个前缀用空格分隔，例如 "/home/data /home/test"
EXCLUDE_PREFIX=${EXCLUDE_PREFIX:-""}

DIR_LIMIT_BYTES=$(( DIR_LIMIT_GB * 1024 * 1024 * 1024 ))
FILE_LIMIT_BYTES=$(( FILE_LIMIT_GB * 1024 * 1024 * 1024 ))

# 颜色定义
BOLD=$(tput bold); PURPLE=$(tput setaf 5); RED=$(tput setaf 1)
CYAN=$(tput setaf 6); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
BAR_COLOR=$(tput setaf 8) 

# --- 辅助函数 ---
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

# 检查是否在排除列表中
is_excluded() {
    local path=$1
    for prefix in $EXCLUDE_PREFIX; do
        if [[ "$path" == "$prefix"* ]]; then
            return 0 # 是排除对象
        fi
    done
    return 1 # 不是排除对象
}

scan_heavy_hitters() {
    local current_path="$1"
    local abs_current=$(realpath "$current_path" 2>/dev/null)
    [[ -z "$abs_current" ]] && return

    # 1. 扫描大文件
    find "$abs_current" -maxdepth 1 -type f -size +"${FILE_LIMIT_GB}"G 2>/dev/null | while read -r file; do
        # 文件也检查排除
        is_excluded "$file" && continue
        
        local f_size=$(stat -c%s "$file" 2>/dev/null)
        [[ -z "$f_size" ]] && continue
        printf "%-10s %s ${PURPLE}%-10s${RESET} 📄 %s\n" \
               "" "$(draw_bar $f_size)" "$(format_size $f_size)" "$file"
    done

    # 2. 扫描大文件夹
    find "$abs_current" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r subdir; do
        local abs_subdir=$(realpath "$subdir")
        
        # 排除检查
        is_excluded "$abs_subdir" && continue

        # 利用 Ceph 扩展属性获取递归大小
        local d_bytes=$(getfattr --absolute-names --only-values -n ceph.dir.rbytes "$abs_subdir" 2>/dev/null)
        [[ -z "$d_bytes" ]] && d_bytes=0

        if [ "$d_bytes" -ge "$DIR_LIMIT_BYTES" ]; then
            printf "%-10s %s ${RED}%-10s${RESET} ${BOLD}📁 %s/${RESET}\n" \
                   "" "$(draw_bar $d_bytes)" "$(format_size $d_bytes)" "$abs_subdir"
            # 递归
            scan_heavy_hitters "$abs_subdir"
        fi
    done
}

# --- 主流程 ---
target_dir="${1:-.}"
[ ! -d "$target_dir" ] && { echo "${RED}错误: 目录 $target_dir 不存在${RESET}"; exit 1; }

abs_root=$(realpath "$target_dir")

echo -e "\n${BLUE}📊 Ceph 深度扫描 (阈值: ${DIR_LIMIT_GB}GB+)${RESET}"
[[ -n "$EXCLUDE_PREFIX" ]] && echo -e "${CYAN}排除前缀: $EXCLUDE_PREFIX${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"

scan_heavy_hitters "$abs_root"

echo -e "${BLUE}----------------------------------------------------------------------${RESET}\n"
