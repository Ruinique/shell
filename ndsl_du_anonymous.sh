#!/bin/bash

# --- 配置 ---
# 只有超过这个大小的才显示 (1GB)
MIN_SHOW_GB=1
MIN_BYTES=$(( MIN_SHOW_GB * 1024 * 1024 * 1024 ))

# 颜色
BOLD=$(tput bold); CYAN=$(tput setaf 6); RED=$(tput setaf 1); RESET=$(tput sgr0)
BAR_COLOR=$(tput setaf 8)

# 格式化
format_size() { numfmt --to=iec-i --suffix=B "$1"; }

# 进度条 (1GB/block, 50GB 封顶)
draw_bar() {
    local gb=$(( $1 / 1024 / 1024 / 1024 ))
    local len=$(( gb > 50 ? 50 : gb ))
    local bar=$(printf '■%.0s' $(seq 1 $len 2>/dev/null))
    printf "${BAR_COLOR}[%-51s]${RESET}" "$bar"
}

main() {
    local base_dir="${1:-/home}"
    
    if [[ ! -d "$base_dir" ]]; then
        echo "错误: 目录 $base_dir 不存在"
        exit 1
    fi

    echo -e "\n${CYAN}${BOLD}📊 Ceph 用户空间占用匿名分析 (Target: $base_dir)${RESET}"
    echo "-----------------------------------------------------------------------"
    printf "${BOLD}%-10s  %-53s  %s${RESET}\n" "SIZE" "USAGE BAR (1 block = 1GB)" "USER_ID"
    
    # 核心逻辑：获取数据 -> 排序 -> 匿名化输出
    find "$base_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r user_dir; do
        # 获取 Ceph 递归属性
        bytes=$(getfattr --absolute-names --only-values -n ceph.dir.rbytes "$user_dir" 2>/dev/null)
        [[ -z "$bytes" ]] && bytes=0
        
        if [ "$bytes" -ge "$MIN_BYTES" ]; then
            # 获取文件夹的 UID 而不是名字
            uid=$(stat -c%u "$user_dir")
            # 格式：字节数|人类可读大小|UID
            echo "$bytes|$(format_size $bytes)|User_$uid"
        fi
    done | sort -rn -t'|' -k1 | while IFS='|' read -r raw_bytes h_size user_tag; do
        # 渲染
        printf "%-10s  %s  %s\n" "$h_size" "$(draw_bar $raw_bytes)" "$user_tag"
    done

    echo "-----------------------------------------------------------------------"
    echo -e "${CYAN}注: 为了隐私，目录名已替换为 User_UID。${RESET}\n"
}

main "$@"
