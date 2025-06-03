WHITELIST=/sdcard/Android/BATTERYOPT/电池优化白名单.prop
LOG_FILE=/sdcard/Android/BATTERYOPT/battery_opt.log

# 确保日志目录存在
mkdir -p /sdcard/Android/BATTERYOPT

# 清理之前的日志文件
rm -f "$LOG_FILE"
touch "$LOG_FILE"

# 添加时间戳的日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 记录详细内容的函数
log_detail() {
    echo -e "\n=== $1 ===" >> "$LOG_FILE"
    echo "$2" >> "$LOG_FILE"
    echo -e "=== 结束 $1 ===\n" >> "$LOG_FILE"
}

log_message "开始执行白名单优化脚本"

if [ -f "$WHITELIST" ]; then
    log_message "读取白名单文件: $WHITELIST"
    
    # 记录原始白名单文件内容
    log_detail "白名单文件原始内容" "$(cat "$WHITELIST")"
    
    # 获取并记录处理后的白名单内容
    whitelist_content=$(cat "$WHITELIST" | grep -v '^#' | cut -f2 -d '=')
    log_detail "处理后的白名单内容" "$whitelist_content"
    
    log_message "获取已安装的第三方应用包名"
    # 获取并记录第三方应用列表
    third_party_apps=$(pm list packages -3 | sed "s/package://g")
    log_detail "已安装的第三方应用列表" "$third_party_apps"
    
    # 处理白名单：先获取所有第三方应用，每个都加上-号
    base_list=$(pm list packages -3 | sed "s/package:/-/g")
    
    # 从白名单内容中提取每个包名并添加+号
    whitelist_apps=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 移除可能存在的+号和空格
        clean_line=$(echo "$line" | sed 's/^[+ ]*//;s/[ ]*$//')
        if [ ! -z "$clean_line" ]; then
            whitelist_apps="$whitelist_apps +$clean_line"
        fi
    done <<< "$whitelist_content"
    
    # 合并基础列表和白名单应用
    whitelist="$base_list$whitelist_apps"
    log_detail "最终白名单内容" "$whitelist"
    
    log_message "设置电池优化白名单"
    dumpsys_output=$(dumpsys deviceidle whitelist $whitelist)
    log_detail "dumpsys执行结果" "$dumpsys_output"
    
    # 验证设置后的白名单
    current_whitelist=$(dumpsys deviceidle whitelist)
    log_detail "当前系统白名单状态" "$current_whitelist"
    
    log_message "白名单设置完成"
else
    log_message "错误：白名单文件不存在 - $WHITELIST"
fi

log_message "脚本执行完成"
