#全局变量
module="/data/adb/modules/crond_start_alipay"
moduleksu="/data/adb/ksu/modules/crond_start_alipay/"
if [[ -d "$module" ]]; then
  mod_path=$module
else
  mod_path=$moduleksu
fi

set_path=${0%/*}
set_file=$set_path/定时设置.ini
cron_d_path=$mod_path/script/set_cron.d
#不存在则创建目录
[[ ! -d $cron_d_path ]] && mkdir -p $cron_d_path

. $mod_path/script/start_alipay_functions.sh

if [[ -f $set_file ]]; then
  . "$set_file"
  if [[ $? != 0 ]]; then
    echo "- [!]: 文件读取异常，请审查(设置定时.ini)文件内容！" && exit 1
  fi
else
  echo "- [!]: 缺少$set_file文件" && exit 2
fi

case "$minute" in
[1-9]*)
  if [[ $minute -le 60 ]]; then
    echo "- 填写正确 | minute=\"$minute\""
  else
    echo "- [!]: 填写错误 | minute=\"$minute\" | 超出60，请重新填写。" && exit 3
  fi
  ;;
*)
  echo "- [!]: 填写错误 | minute=\"$minute\" | 请重新填写(5..60)。" && exit 4
  ;;
esac

case "$what_time_run" in
y | n) echo "- 填写正确 | what_time_run=\"$what_time_run\"" ;;
*) echo "- [!]: 填写错误 | what_time_run=\"$what_time_run\" | 请填写y或n" && exit 5 ;;
esac

CN_AMPM() {
  case "$1" in
  1 | 3 | 4 | 5) alias $2="凌晨" ;;
  6 | 7 | 8 | 9) alias $2="早上" ;;
  10 | 11) alias $2="上午" ;;
  12) alias $2="中午" ;;
  13 | 14 | 15 | 16 | 17) alias $2="下午" ;;
  18 | 19 | 20 | 21 | 22 | 23 | 0) alias $2="晚上" ;;
  esac
}

if [[ $what_time_run == y ]]; then
  what_time_1=$(echo "$what_time" | awk -F "-" '{print $1}')
  what_time_2=$(echo "$what_time" | awk -F "-" '{print $2}')
  if [[ -z "$what_time_1" ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 格式: 几点-几点"
    exit 6
  elif [[ -z "$what_time_2" ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 格式: 几点-几点"
    exit 7
  elif [[ -z $(echo $what_time_1 | grep "[0-9]") ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 填写数字(几点-几点)，不要写汉字！"
    exit 8
  elif [[ -z $(echo $what_time_2 | grep "[0-9]") ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 填写数字(几点-几点)，不要写汉字！"
    exit 9
  elif [[ ${#what_time_1} -ge 3 ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 填写数字(整数-整数)，不要超过3个字符！"
    exit 10
  elif [[ ${#what_time_2} -ge 3 ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 填写数字(整数-整数)，不要超过3个字符！"
    exit 11
  elif [[ "$what_time_1" == "$what_time_2" ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 几点-几点 时间不能相同！"
    exit 12
  elif [[ "$what_time_1" -ge 24 ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 时间不能大于或等于24点 这里的24点是0点"
    exit 13
  elif [[ "$what_time_2" -ge 24 ]]; then
    echo "- [!]: 填写错误 | what_time=\"$what_time\" | 时间不能大于或等于24点 这里的24点是0点"
    exit 14
  else
    echo "- 填写正确 | what_time=\"$what_time\""
  fi
  #输出必要信息
  [[ $what_time_1 -gt $what_time_2 ]] && cn_text="第二天" || cn_text=""
  [[ $what_time_2 == 0 ]] && cn_text=""
  CN_AMPM "$what_time_1" "time_period_1"
  CN_AMPM "$what_time_2" "time_period_2"
  #输出必要信息
  logd_ini="minute=\"$minute\" | what_time_run=\"$what_time_run\" | what_time=\"$what_time\""
  crond_rule="*/$minute $what_time * * *"
  print_set="每天${time_period_1}${what_time_1}:00到${cn_text}${time_period_2}${what_time_2}:59，每隔${minute}分钟运行一次。"
else
  #输出必要信息
  logd_ini="minute=\"$minute\" | what_time_run=\"$what_time_run\""
  crond_rule="*/$minute * * * *"
  print_set="24H 每隔${minute}分钟运行一次"
fi

echo "- 定时设置 | $crond_rule"
echo "- 内容解读 | $print_set"
echo "$print_set" > $mod_path/print_set

start_alipay_crond_pid_1="$(ps -ef | grep -v 'grep' | grep 'crond' | grep 'crond_start_alipay' | awk '{print $2}')"
if [[ -n $start_alipay_crond_pid_1 ]]; then
  echo "- 杀死上次定时 | pid: $start_alipay_crond_pid_1"
  kill -9 "$start_alipay_crond_pid_1"
fi

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

#开启定时
echo "$crond_rule $mod_path/script/Run_alipay.sh" > $cron_d_path/root
rm -rf $mod_path/script/cron.d/root
crond -c "$cron_d_path"
start_alipay_crond_pid_2="$(ps -ef | grep -v 'grep' | grep 'crond' | grep 'crond_start_alipay' | awk '{print $2}')"
echo "- 定时启动成功 | pid: $start_alipay_crond_pid_2"
log_md_set_cron_clear
if [[ -f $mod_path/script/Run_alipay.sh ]]; then
  sh $mod_path/script/Run_alipay.sh > /dev/null
else
  echo "- 模块脚本缺失！"
fi
