#全局变量
MODDIR=${0%/*}
#注入sh进程
. "$MODDIR"/script/start_alipay_functions.sh

#定义变量
if [[ -f "/data/adb/ksud" ]]; then
  S=$(/data/adb/ksud -V | awk '/ksud/{gsub("ksud ", ""); print substr($0,1,4)}')
  if [[ "$S" = "v0.3" ]]; then
    alias crond="/data/adb/busybox/crond"
  else
    alias crond="/data/adb/busybox/crond"
  fi
else
  alias crond="\$( magisk --path )/.magisk/busybox/crond"
fi

logd "初始化完成: [initial.sh]"

if [[ -f "$MODDIR"/script/set_cron.d/root ]]; then
  if [[ -f "$MODDIR"/script/cron.d/root ]]; then
    rm -rf "$MODDIR"/script/cron.d/root
  fi
  crond -c "$MODDIR"/script/set_cron.d
  crond_root_file=$MODDIR/script/set_cron.d/root
else
  echo "默认: 24H 每隔1小时运行一次" > "$MODDIR"/print_set
  echo "0 */1 * * * $MODDIR/script/Run_alipay.sh" > "$MODDIR"/script/cron.d/root
  crond -c "$MODDIR"/script/cron.d
  crond_root_file=$MODDIR/script/cron.d/root
fi

sleep 1

if [[ $(pgrep -f "crond_start_alipay/script/cron.d" | grep -vc grep) -ge 1 ]]; then
  basic_Information
  logd "$(cat "$MODDIR"/print_set)"
  logd "开始运行: [$crond_root_file]"
  logd "------------------------------------------------------------"
elif [[ $(pgrep -f "crond_start_alipay/script/set_cron.d" | grep -vc grep) -ge 1 ]]; then
  basic_Information
  logd "$(cat "$MODDIR"/print_set)"
  logd "开始运行: [$crond_root_file]"
  logd "------------------------------------------------------------"
else
  basic_Information
  logd "运行失败！"
  exit 1
fi

sh "$MODDIR"/script/Run_alipay.sh
