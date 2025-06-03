MyPrint() {
  echo "$@"
  sleep 0.05
}

MyPrint " "
MyPrint "╔════════════════════════════════════"
MyPrint "║   - [&]请先阅读 避免一些不必要的问题"
MyPrint "╠════════════════════════════════════"
MyPrint "║"
MyPrint "║   - 1.模块刷入重启后，只在用户解锁设备才开始生效。"
MyPrint "║   - 2.使用crond定时命令，不会浪费或占用系统资源。"
MyPrint "║   - 3.模块自定义路径: /sdcard/Android/clear_the_blacklist/"
MyPrint "║ "
MyPrint "║   - https://github.com/Petit-Abba/black_and_white_list/"
MyPrint "║ "
MyPrint "╚════════════════════════════════════"
MyPrint " "
#文件夹类型
black_and_white_list_path="/sdcard/Android/clear_the_blacklist"
black_and_white_list_path_old="/sdcard/Android/clear_the_blacklist_old"
cron_set_dir="${black_and_white_list_path}/定时任务"

#文件类型
Black_List="${black_and_white_list_path}/黑名单.prop"
White_List="${black_and_white_list_path}/白名单.prop"

cron_set_file="${cron_set_dir}/定时设置.ini"
Run_cron_sh="${cron_set_dir}/Run_cron.sh"

magisk_util_functions="/data/adb/magisk/util_functions.sh"
grep -q 'lite_modules' "${magisk_util_functions}" && modules_path="lite_modules" || modules_path="modules"
mod_path="/data/adb/${modules_path}/crond_clear_the_blacklist"
script_dir="${mod_path}/script"

# 判断是否安装过
if [[ -d ${script_dir}/tmp/DATE ]] && [[ -d ${black_and_white_list_path} ]]; then
  mkdir -p "$black_and_white_list_path_old/定时任务"
  cp -f "$Black_List" "$black_and_white_list_path_old"
  cp -f "$White_List" "$black_and_white_list_path_old"
  cp -rf "$cron_set_dir" "$black_and_white_list_path_old"
  rm -rf "$Black_List"
  rm -rf "$White_List"
  rm -rf "$cron_set_dir"
  MyPrint "检测到安装过模块，旧配置文件已经自动备份。"
fi

#获取ksu的busybox地址
busybox="/data/adb/ksu/bin/busybox"
#释放地址
filepath="/data/adb/busybox"
#如果没有此文件夹则创建
#检查Busybox并释放
if [[ -f $busybox ]]; then
  if [[ ! -f $filepath ]]; then
    mkdir -p "$filepath"
  fi
  #存在Busybox开始释放
  "$busybox" --install -s "$filepath"
  MyPrint "已安装busybox。"
fi

[[ -d ${cron_set_dir} ]] || mkdir -p ${cron_set_dir}
[[ -f ${Black_List} ]] || cp -r "${MODPATH}"/AndroidFile/黑名单.prop ${black_and_white_list_path}/
[[ -f ${White_List} ]] || cp -r "${MODPATH}"/AndroidFile/白名单.prop ${black_and_white_list_path}/
[[ -f ${cron_set_file} ]] || cp -r "${MODPATH}"/AndroidFile/定时任务/定时设置.ini ${cron_set_dir}/
[[ -f ${Run_cron_sh} ]] && rm -rf ${Run_cron_sh}
cp -r "${MODPATH}"/AndroidFile/定时任务/Run_cron.sh ${cron_set_dir}/
rm -rf "${MODPATH}"/AndroidFile/
