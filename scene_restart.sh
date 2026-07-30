#!/system/bin/sh
# ======================================================
#  Scene 守护进程重启脚本（模块版）
#  基于 Scene 原生 up.sh，修复 kill_old_daemon 未调用
#  导致的 scene-daemon 进程反复堆积问题
# ======================================================

scene="com.omarea.vtools"
daemon="scene-daemon"

current_dir=$(dirname $0)
update_path="$current_dir/$daemon-bak"
origin_path="$current_dir/$daemon"

# ========== 【修复】kill old daemon（基于 /proc 扫描，不依赖外部工具） ==========
# 修复项: 原生 up.sh 在第91行定义了此函数但从未调用
#         且仅用 ss 查端口8765，漏杀未绑定端口的进程
# 本版:  移到脚本顶部，在启动 daemon 前调用；
#         使用 /proc 遍历所有 scene-daemon 进程，全杀
kill_old_daemon(){
  local killed=0

  # 方法1: 遍历所有进程，匹配 comm 和 cmdline
  for pid_dir in /proc/[0-9]*; do
    [ -d "$pid_dir" ] || continue
    local pid=$(basename "$pid_dir")

    # 跳过自身
    [ "$pid" = "$$" ] && continue

    # 检查 comm（最多15字符，精确匹配）
    local comm=$(cat "$pid_dir/comm" 2>/dev/null)

    # 检查 cmdline（子串匹配，兜底 comm 被截断）
    local cmd=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null)

    local should_kill=0
    case "$cmd" in
      *"$daemon"*)
        should_kill=1
        ;;
    esac

    if [ "$comm" = "$daemon" ]; then
      should_kill=1
    fi

    if [ "$should_kill" = "1" ]; then
      kill -9 "$pid" 2>/dev/null && killed=$((killed + 1))
    fi
  done

  # 方法2: 如果 pkill/killall 可用（PATH 已含 toolkit），追加清理
  if command -v pkill >/dev/null 2>&1; then
    while pkill -9 -x "$daemon" 2>/dev/null; do
      sleep 0.1
    done
  fi

  if command -v killall >/dev/null 2>&1; then
    killall -9 "$daemon" 2>/dev/null
  fi
}


if [[ ! -e "$origin_path" ]];then
  echo "$origin_path not found !"
  exit 1
fi

dumpsys deviceidle whitelist +$scene 2>&1 >/dev/null
cmd appops set $scene RUN_IN_BACKGROUND allow 2>&1 >/dev/null
cmd appops set $scene RUN_ANY_IN_BACKGROUND allow 2>&1 >/dev/null
am set-standby-bucket $scene active 2>&1 >/dev/null
am set-inactive --user 0 $scene false 2>&1 >/dev/null
am set-bg-restriction-level --user 0 $scene unrestricted 2>&1 >/dev/null
am set-foreground-service-delegate --user 0 com.omarea.vtools start 2>&1 >/dev/null
am unfreeze --sticky com.omarea.vtools 2>&1 >/dev/null

toolkit_dir=$current_dir/toolkit

# ---------- 提前设置 PATH（确保后续 pkill/killall 可用）----------
if [[ $(echo "$PATH" | grep 'toolkit') == '' ]] && [[ -d "$toolkit_dir" ]]; then
  export PATH=$PATH:$toolkit_dir
fi

# ===== 【修复】杀掉所有旧 scene-daemon 进程（原生 up.sh 漏掉了这一步） =====
kill_old_daemon

touch "/cache/USER-NAME" 2> /dev/null
if [[ "$?" == "0" ]] || [[ "$USER" == "ROOT" ]] || [[ "$USER" == "root" ]]; then
  if [[ -f $update_path ]]; then
    rm -f "$origin_path" 2>/dev/null
    killall -9 $daemon 2>/dev/null
    mv -f "$update_path" "$origin_path"
    killall -9 $daemon 2>/dev/null
  fi
  if [[ "$(ksud -V 2>/dev/null)" != '' ]]; then
    export KSU=true
    echo 'export KSU=true'
    ksu=/data/adb/ksu/bin
    if [[ $(echo "$PATH" | grep $ksu) == "" ]]; then
      export PATH=$PATH:$ksu
    fi
  fi
  debugfs=$(grep -e "^debugfs" /proc/mounts | head -1 | awk '{print $2}')
  if [[ "$debugfs" == '' ]]; then
    name1=$(cat /dev/urandom | tr -dc 'a-z_' | head -c 8; echo)
    name2=$(cat /dev/urandom | tr -dc 'a-z_' | head -c 8; echo)
    scene_tmp=/dev/$name1
    debugfs="$scene_tmp/$name2"
    if [ -d /data/adb/modules/dimensity_hybrid_governor ]; then
      scene_tmp=/dev/scene
      debugfs="$scene_tmp/debug"
    fi
    mkdir -p "$debugfs"
    mount -t debugfs debugfs "$debugfs" -o mode=755
    chmod 600 "$scene_tmp"
  fi
  if [[ -d /proc/oplus-votable/GAUGE_UPDATE ]]; then
    echo 1000 > /proc/oplus-votable/GAUGE_UPDATE/force_val
    echo 1 > /proc/oplus-votable/GAUGE_UPDATE/force_active
  fi
  if [[ "$1" == "debug" ]]; then
    echo 'Scene-Daemon Starting……'
    $origin_path
  else
    log_path=$current_dir/daemon.log
    if [[ -f $log_path ]]; then
      if [[ -f $current_dir/daemon.stderr.log ]]; then
        rm $current_dir/daemon.stderr.log
      fi
      mv $log_path $current_dir/daemon.stderr.log
    fi
    nohup $origin_path >/dev/null 2>$log_path &
    renice -n -20 $(pidof scene-daemon)
    echo 'Scene-Daemon OK!'
  fi
else
  cache_dir="/data/local/tmp"

  killall -9 $daemon 2>/dev/null

  echo ''
  toolkit=$cache_dir/toolkit
  mkdir -p $toolkit
  # Env PATH add /data/local/tmp
  export PATH=$PATH:$toolkit

  if [[ -f "$current_dir/busybox" ]] && [[ ! -f $toolkit/busybox ]]; then
    echo 'Copy BusyBox'
    cp "$current_dir/busybox" $toolkit/busybox
    chmod 777 $toolkit/busybox

    echo 'Install BusyBox……'
    cd $toolkit
    for applet in `./busybox --list`; do
      case "$applet" in
      "sh"|"busybox"|"shell"|"swapon"|"swapoff"|"mkswap")
        echo '  Skip' > /dev/null
      ;;
      *)
        ./busybox ln -sf busybox "$applet";
      ;;
      esac
    done
    ./busybox ln -sf busybox busybox_1_34_1
  fi

  if [[ -f "$current_dir/binder.so" ]]; then
    cp -f "$current_dir/binder.so" $cache_dir/binder.so
  fi

  target_path="$cache_dir/$daemon"
  echo "Origin File: " $origin_path
  echo "Target File: " $target_path
  echo ''

  cp $origin_path $target_path
  chmod 777 $target_path
  nohup $target_path >/dev/null 2>&1 &
  if [[ $(pgrep scene-daemon) != "" ]]; then
    echo 'Scene-Daemon OK! ^_^'
  else
    echo 'Scene-Daemon Fail! @_@'
  fi

  am start -n $scene/.activities.ActivityStartSplash -f 0x10008000
  cmd package compile -m speed $scene >/dev/null 2>&1 &
fi
