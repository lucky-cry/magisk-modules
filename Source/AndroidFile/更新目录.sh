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