WHITELIST=/sdcard/Android/BATTERYOPT/电池优化白名单.prop

if [ -f "$WHITELIST" ]; then
    # 获取处理后的白名单内容
    whitelist_content=$(cat "$WHITELIST" | grep -v '^#' | cut -f2 -d '=')
    
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
    
    # 合并基础列表和白名单应用并应用
    whitelist="$base_list$whitelist_apps"
    dumpsys deviceidle whitelist $whitelist
fi
