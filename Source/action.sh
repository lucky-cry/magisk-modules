#!/system/bin/sh

# 定义两个可选的 updateJson URL
GITEE_URL="https://gitee.com/lucky__cat/magisk-modules/raw/Hcfile_sharing/update.json"
GITHUB_URL="https://raw.githubusercontent.com/lucky-cry/magisk-modules/Hcfile_sharing/update.json"

# 切换 updateJson 的函数
switch_update_json() {
    MODULE_PROP="/data/adb/modules/Hcfile_sharing/module.prop"
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

# 原有的模块更新功能
magisk=/data/adb/magisk/busybox
kernelsu=/data/adb/ksu/bin/busybox
apatch=/data/adb/ap/bin/busybox
killall bcccccccc
if [ -f $magisk ]; then
    echo -n '当前环境为：Magisk 正在更新……'
    /data/adb/magisk/busybox sh '/data/adb/modules/Hcfile_sharing/B.sh' nosleep
    echo '当前环境为：Magisk 目录更新完成'
    echo '注意：请在Magisk设置中把 挂载命名空间模式 设置为 全局命名空间，否则只能在当前应用查看更新，重启后才能生效'
elif [ -f $kernelsu ]; then
    echo -n '当前环境为：KernelSU 正在更新……'
    /data/adb/ksu/bin/busybox sh '/data/adb/modules/Hcfile_sharing/B.sh' nosleep
    echo '当前环境为：KernelSU 目录更新完成'
elif [ -f $apatch ]; then
    echo -n '当前环境为：Apatch 正在更新……'
    /data/adb/ap/bin/busybox sh '/data/adb/modules/Hcfile_sharing/B.sh' nosleep
    echo '当前环境为：Apatch 目录更新完成'
else
    echo '未知环境，未适配！！！'
fi