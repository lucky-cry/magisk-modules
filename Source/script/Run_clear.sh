#全局变量
MODDIR=${0%/*}
# 跳过白名单次数判断
print_pd_white_list() {
  white_file="$MODDIR/White_List_File/$(echo "$1" | sed 's/\///g').ini"
  if [[ ! -e "$white_file" ]]; then
    echo "1" > "$white_file"
    logd "[continue] -[$(cat "$white_file")]- $2"
  else
    echo "- [continue]: $1"
    # 小于3次则打印
    if [[ "$(cat "$white_file")" -lt "3" ]]; then
      echo "$(($(cat "$white_file") + 1))" > "$white_file"
      logd "[continue] -[$(cat "$white_file")]- $2"
    fi
  fi
}

# 小米应用商店文件夹判断
com_xiaomi_market() {
  if [[ ! -z "$(echo "$1" | grep -w "com.xiaomi.market")" ]]; then
    if [[ "$(find "$1" -name "*.apk")" != "" ]]; then
      logd "存在APK: $1"
      return 2
    fi
  fi
}

# 寻找black文件位置
main_find_black() {
  local IFS=$'\n'
  find_black="$(find /data/media/ -type f -name 'black')"
  if [[ ! -z $find_black ]]; then
    identifier="$(cat $Black_List | grep -w '#black标识符')"
    [[ -z $identifier ]] && echo "#black标识符" >> $Black_List
    for black_file_path in $find_black; do
      BLACK="${black_file_path%/black}"
      if [[ ! -z "$(cat $White_List | grep "$BLACK")" ]]; then
        logd "[continue black] --白名单DIR: $BLACK"
        continue
      fi
      logd "[add black] --黑名单DIR: $BLACK/"
      sed -i "/$identifier/a$BLACK/" "$Black_List"
    done
  fi
}

# 白名单列表通配符拓展
whitelist_wildcard_list() {
  local IFS=$'\n'
  for wh in $(cat $White_List | grep -v '#'); do
    echo "$wh"
  done
}

# 黑名单列表通配符拓展
blacklist_wildcard_list() {
  local IFS=$'\n'
  for bl in $(cat $Black_List | grep -v '#'); do
    echo "$bl"
  done
}
#主程序
main_for() {
  # 重新定义字段分隔符 忽略空格和制表符
  local IFS=$'\n'
  # 因为重新定义字段分隔符 所以只需要for 不再需要while read
  for i in $(echo "$Black_List_Expand" | grep -v '*'); do
    # 文件夹
    if [[ -d "$i" ]]; then
      case $i in *'/.') continue ;; *'/./') continue ;; *'/..') continue ;; *'/../') continue ;; esac
      if [[ ! -z $(echo "$White_List_Expand" | grep -w "$i") ]]; then
        print_pd_white_list "$i" "白名单DIR: $i"
        continue
      fi
      com_xiaomi_market "$i"
      [[ $? == 2 ]] && continue
      rm -rf "$i" && {
        let DIR++
        logd "[rm] --黑名单DIR: $i"
        echo "$DIR" > $tmp_date/dir
      }
    fi
    # 文件
    if [[ -f "$i" ]]; then
      if [[ ! -z $(echo "$White_List_Expand" | grep -w "$i") ]]; then
        print_pd_white_list "$i" "白名单FILE: $i"
        continue
      fi
      rm -rf "$i" && {
        let FILE++
        logd "[rm] --黑名单FILE: $i"
        echo "$FILE" > $tmp_date/file
      }
    fi
  done
}

. "$MODDIR/clear_the_blacklist_functions.sh"

if [[ "$Screen" == "亮屏" ]]; then
  echo "- 亮屏状态"
  if [[ ! -f $MODDIR/tmp/Screen_on ]]; then
    echo "true" > "$MODDIR"/tmp/Screen_on
    logd "[状态]: [$Screen] 执行"
  fi
  #创建白名单拦截次数记录文件
  if [[ ! -d $MODDIR/White_List_File ]]; then
    mkdir -p "$MODDIR"/White_List_File
  fi

  if [[ ! -d $MODDIR/tmp/DATE ]]; then
    mkdir -p "$MODDIR"/tmp/DATE
  fi

  tmp_date="$MODDIR/tmp/DATE/$(date '+%Y%m%d')"

  if [[ ! -d "$tmp_date" ]]; then
    rm -rf "$MODDIR"/tmp/DATE/*/ > /dev/null 2>&1
    mkdir -p "$tmp_date"
    echo "0" > "$tmp_date"/file
    echo "0" > "$tmp_date"/dir
    # 文件大小
    #filesize="$(ls -l ${log} | awk '{print $5}')"
    # 3kb
    #maxsize="$((1024*3))"
    #[[ $filesize -gt $maxsize ]] &&
    log_md_clear
  fi

  FILE="$(cat "$tmp_date"/file)"
  DIR="$(cat "$tmp_date"/dir)"

  main_find_black
  White_List_Expand="$(whitelist_wildcard_list)"
  Black_List_Expand="$(blacklist_wildcard_list)"
  # 执行方法
  main_for

  FILE="$(cat "$tmp_date"/file)"
  DIR="$(cat "$tmp_date"/dir)"
  sed -i "/^description=/c description=CROND: ✨今日已清除: $FILE个叼毛文件 | $DIR个叼毛文件夹 ✨" "${MODDIR%/script}/module.prop"
else
  echo "- 息屏状态"
  if [[ -f $MODDIR/tmp/Screen_on ]]; then
    rm -rf "$MODDIR"/tmp/Screen_on
    logd "[状态]: [$Screen] 不执行"
  fi
fi
