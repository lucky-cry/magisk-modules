#!/system/bin/sh
# Magisk模块更新检测脚本
# 将此脚本放入模块目录中，并在module.prop中设置updateJson

MODULE_DIR=${0%/*}
MODULE_PROP="$MODULE_DIR/module.prop"

# 检查module.prop是否存在
if [ ! -f "$MODULE_PROP" ]; then
  echo "错误: 找不到module.prop文件"
  exit 1
fi

# 从module.prop获取信息
MODULE_ID=$(grep -E "^id=" "$MODULE_PROP" | cut -d= -f2)
MODULE_VERSION=$(grep -E "^version=" "$MODULE_PROP" | cut -d= -f2)
MODULE_VERSIONCODE=$(grep -E "^versionCode=" "$MODULE_PROP" | cut -d= -f2)
UPDATE_JSON=$(grep -E "^updateJson=" "$MODULE_PROP" | cut -d= -f2)

if [ -z "$UPDATE_JSON" ]; then
  echo "错误: module.prop中未设置updateJson"
  exit 1
fi

echo "正在检查模块 $MODULE_ID ($MODULE_VERSION) 的更新..."

# 使用curl下载更新信息
JSON_FILE="$MODULE_DIR/update_info.json"
curl -s -o "$JSON_FILE" "$UPDATE_JSON"

if [ ! -f "$JSON_FILE" ]; then
  echo "错误: 无法下载更新信息"
  exit 1
fi

# 解析JSON (简单方法，实际应用可能需要更健壮的解析)
NEW_VERSION=$(grep -E '"version"' "$JSON_FILE" | cut -d '"' -f4)
NEW_VERSIONCODE=$(grep -E '"versionCode"' "$JSON_FILE" | sed 's/[^0-9]//g')
ZIP_URL=$(grep -E '"zipUrl"' "$JSON_FILE" | cut -d '"' -f4)
CHANGELOG=$(grep -E '"changelog"' "$JSON_FILE" | cut -d '"' -f4)

# 清理临时文件
rm -f "$JSON_FILE"

# 比较版本
if [ "$NEW_VERSIONCODE" -gt "$MODULE_VERSIONCODE" ]; then
  echo "发现新版本: $NEW_VERSION (当前版本: $MODULE_VERSION)"
  echo "下载地址: $ZIP_URL"
  echo "更新日志: $CHANGELOG"
  
  # 询问是否下载更新
  echo "是否下载更新? (y/n)"
  read -r ANSWER
  
  if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
    echo "正在下载更新..."
    DOWNLOAD_PATH="/sdcard/Download/${MODULE_ID}-${NEW_VERSION}.zip"
    curl -L -o "$DOWNLOAD_PATH" "$ZIP_URL"
    
    if [ -f "$DOWNLOAD_PATH" ]; then
      echo "下载完成: $DOWNLOAD_PATH"
      echo "请在Magisk Manager中手动安装此更新"
    else
      echo "下载失败"
    fi
  fi
else
  echo "已是最新版本: $MODULE_VERSION"
fi
