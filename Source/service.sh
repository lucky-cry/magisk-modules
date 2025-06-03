#!/system/bin/sh
MODDIR=${0%/*}
#赋权才能正常运行
chmod -R 0777 "$MODDIR"
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

WHITELIST=/sdcard/Android/BATTERYOPT/电池优化白名单.prop

if [ ! -f $WHITELIST ]; then
	mkdir /sdcard/Android/BATTERYOPT
	touch $WHITELIST
	echo "#加入包名，前面加＋号，如 +com.itisaapp.and" >$WHITELIST
fi

export PATH="/system/bin:/system/xbin:/vendor/bin:$(magisk --path)/.magisk/busybox:$PATH"
crond -c $MODDIR/cron.d
