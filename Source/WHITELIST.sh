WHITELIST=/sdcard/Android/BATTERYOPT/电池优化白名单.prop
LOG_FILE=/sdcard/Android/BATTERYOPT/battery_opt.log

# 确保日志目录存在
mkdir -p /sdcard/Android/BATTERYOPT

# 添加时间戳的日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "开始执行白名单优化脚本"

if [ -f "$WHITELIST" ]; then
    log_message "读取白名单文件: $WHITELIST"
    whitelist=$(cat "$WHITELIST" | grep -v '^#' | cut -f2 -d '=')
    log_message "获取已安装的第三方应用包名"
    whitelist=`pm list packages -3 | sed "s/package:/-/g"`"$whitelist"
    log_message "设置电池优化白名单"
    dumpsys deviceidle whitelist $whitelist
    log_message "白名单设置完成"
else
    log_message "错误：白名单文件不存在 - $WHITELIST"
fi

log_message "脚本执行完成"
