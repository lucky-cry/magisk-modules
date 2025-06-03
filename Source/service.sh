#全局变量
MODDIR=${0%/*}
#等待用户登录
Wait_until_login() {
  # in case of /data encryption is disabled
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
  done

  # in case of the user unlocked the screen
  while [ ! -d "/sdcard/Android" ]; do
    sleep 1
  done
}
Wait_until_login

#赋权才能正常运行
chmod -R 0777 "$MODDIR"
#删除历史遗留文件
if [[ -f "$MODDIR"/script/tmp/Screen_on ]]; then
  rm -rf "$MODDIR"/script/tmp/Screen_on
fi
#注入sh进程
. "$MODDIR"/script/clear_the_blacklist_functions.sh
#清空log
logd_clear "开机启动完成: [service.sh]"

sh "$MODDIR"/initial.sh
