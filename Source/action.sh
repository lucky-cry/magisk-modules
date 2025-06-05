#!/system/bin/sh

# 定义两个可选的 updateJson URL
GITEE_URL="https://gitee.com/lucky__cat/magisk-modules/raw/crond_start_alipay/update.json"
GITHUB_URL="https://raw.githubusercontent.com/lucky-cry/magisk-modules/crond_start_alipay/update.json"

# 切换 updateJson 的函数
switch_update_json() {
    MODULE_PROP="/data/adb/modules/crond_start_alipay/module.prop"
    CURRENT_URL=$(grep "updateJson=" "$MODULE_PROP" | cut -d= -f2)
    
    if [ "$CURRENT_URL" = "$GITEE_URL" ]; then
        # 切换到 GitHub URL
        sed -i "s|updateJson=.*|updateJson=$GITHUB_URL|g" "$MODULE_PROP"
        echo "已切换到 GitHub 更新源"
    else
        # 切换到 Gitee URL（默认）
        sed -i "s|updateJson=.*|updateJson=$GITEE_URL|g" "$MODULE_PROP"
        echo "已切换到 Gitee 更新源（默认）"
    fi
}

# 执行更新源切换
switch_update_json