#!/system/bin/sh
# ======================================================
#  lib_core.sh - 函数库（日志 / 检测 / cgroup / 恢复）
#  被 service.sh 加载，所有函数在这里定义
#  修改此文件后重启 service 即可生效，无需重启手机
# ======================================================

# ========== 等待用户解锁设备 ==========
Wait_until_login() {
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
  done
  until [ -d /sdcard/Android ]; do
    sleep 5
  done
}

# ========== 日志函数 ==========
log_clear() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  echo "[$(date '+%y/%m/%d %H:%M:%S')] | $*" > "$LOG_FILE" 2>/dev/null
}

log() {
  echo "[$(date '+%y/%m/%d %H:%M:%S')] | $*" >> "$LOG_FILE" 2>/dev/null
}

log_debug() { log "DEBUG: $*"; }
log_info()  { log "INFO: $*"; }
log_error() { log "ERROR: $*"; }

# ========== 屏幕检测 ==========
is_screen_on() {
  local status=$(timeout 3 dumpsys window policy 2>/dev/null | grep 'mInputRestricted' | cut -d= -f2)
  [ "$status" != "true" ]
}

# ========== PID 文件（防重复启动） ==========
check_running() {
  if [ -f "${PID_FILE}" ]; then
    local old_pid
    read -r old_pid < "${PID_FILE}" 2>/dev/null
    if [ -n "${old_pid}" ] && [ -d "/proc/${old_pid}" ]; then
      if grep -qF "service.sh" "/proc/${old_pid}/cmdline" 2>/dev/null; then
        log_info "service.sh 已在运行 (PID: ${old_pid})，退出"
        exit 0
      fi
    fi
    rm -f "${PID_FILE}" 2>/dev/null
    log_debug "过期 PID 文件已删除"
  fi
  echo $$ > "${PID_FILE}"
}

# ========== 进程检测（pidof，极快无阻塞） ==========
check_daemon_process() {
  [ -z "${DAEMON_NAME}" ] && { log_error "目标进程名为空！"; return 1; }

  local pids=$(pidof "$DAEMON_NAME" 2>/dev/null)
  if [ -n "$pids" ]; then
    log_debug "检测到 $DAEMON_NAME (PID=$pids)"
    return 0
  fi

  log_debug "$DAEMON_NAME 未找到"
  return 1
}

# ========== 获取 logd 主 PID ==========
get_logd_pid() {
  pidof logd 2>/dev/null | awk '{print $1}'
}

# ========== Scene 卡死判定 ==========
# 返回 0=正常, 1=卡死
# 卡死条件: scene-daemon 进程数>3 且 两个日志文件行数均<2
# 其余情况一律视为正常
is_scene_normal() {
  # 未安装 → 不卡死
  [ -d "/data/data/${SCENE_PKG}" ] || return 0

  local scene_files="/data/data/com.omarea.vtools/files"
  local stderr_state="不存在"
  local daemon_state="不存在"
  local stderr_lines=0
  local daemon_lines=0

  # 检测 daemon.stderr.log
  local stderr_log="$scene_files/daemon.stderr.log"
  if [ -f "$stderr_log" ]; then
    stderr_lines=$(timeout 3 wc -l < "$stderr_log" 2>/dev/null | tr -d '[:space:]')
    stderr_lines=${stderr_lines:-0}
    [ "$stderr_lines" -gt 1 ] && stderr_state="${stderr_lines}行 ✓" || stderr_state="${stderr_lines}行 ✗"
  fi

  # 检测 daemon.log
  local daemon_log="$scene_files/daemon.log"
  if [ -f "$daemon_log" ]; then
    daemon_lines=$(timeout 3 wc -l < "$daemon_log" 2>/dev/null | tr -d '[:space:]')
    daemon_lines=${daemon_lines:-0}
    [ "$daemon_lines" -gt 1 ] && daemon_state="${daemon_lines}行 ✓" || daemon_state="${daemon_lines}行 ✗"
  fi

  # 卡死判定: pid>3 且 两个日志均 <2 行
  local pid_count=$(pidof "$DAEMON_NAME" 2>/dev/null | wc -w)
  pid_count=${pid_count:-0}
  if [ "$pid_count" -gt 3 ] && [ "$stderr_lines" -lt 2 ] && [ "$daemon_lines" -lt 2 ]; then
    log_debug "Scene 卡死: 进程数=$pid_count, stderr=${stderr_state}, daemon=${daemon_state}"
    return 1
  fi

  log_debug "Scene 正常: 进程数=$pid_count, stderr=${stderr_state}, daemon=${daemon_state}"
  return 0
}

# ========== cgroup 冻结/解冻 ==========

is_frozen() {
  [ -f "$FREEZEFILE" ] && [ "$(cat "$FREEZEFILE")" = "1" ]
}

freeze_logd() {
  local pid="$1"
  mkdir -p "$CGPATH"
  echo "+freezer" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null
  echo "$pid" > "$CGPATH/cgroup.procs" 2>/dev/null || { log_error "写入 cgroup.procs 失败"; return 1; }
  echo 1 > "$FREEZEFILE" 2>/dev/null || { log_error "写入 cgroup.freeze 失败"; return 1; }
  sed -i "s/^description=.*/description=logd 已冻结（循环监控） | 点击按钮解冻/" "$MODDIR/module.prop" 2>/dev/null
  log "freeze_logd: PID=$pid 已冻结, cgroup.freeze=$(cat "$FREEZEFILE" 2>/dev/null), module.prop 已同步"
}

unfreeze_logd() {
  [ -f "$FREEZEFILE" ] && echo 0 > "$FREEZEFILE"
  local pid=$(get_logd_pid)
  [ -n "$pid" ] && echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  rmdir "$CGPATH" 2>/dev/null
  sed -i "s/^description=.*/description=logd 已解冻 | 点击按钮冻结/" "$MODDIR/module.prop" 2>/dev/null
  log "unfreeze_logd: logd 已解冻, cgroup子目录已清理, module.prop 已同步"
}

# ========== 重启 Scene 守护进程 ==========
restart_scene_daemon() {
  local scene_restart="/data/data/com.omarea.vtools/files/重启.sh"
  local module_backup="$MODDIR/scene_restart.sh"

  # 始终覆盖为模块版（避免 Scene 原生脚本不杀旧进程导致僵尸堆积）
  if [ -f "$module_backup" ]; then
    cp -f "$module_backup" "$scene_restart"
    chmod 755 "$scene_restart"
    log_info "已部署模块版重启脚本 (覆盖原生)"
  else
    log_error "模块备份不存在: $module_backup"
    return 1
  fi

  log_info "执行: sh $scene_restart"
  sh "$scene_restart" >/dev/null 2>&1 &
  log_info "重启脚本已启动 (返回码=$?)"
  sleep 3
}

# ========== 恢复流程（渐进式冻结延迟） ==========
do_recovery() {
  log "===== 开始 Scene 异常恢复 ====="

  # 互斥锁: 防止 crond 并发多个实例并行执行
  # 锁目录 /data/local/tmp/freeze_recovery_lock/ 存在即锁定
  # 内含 pid 文件用于僵尸锁检测
  local RECOVERY_LOCK="/data/local/tmp/freeze_recovery_lock"
  if ! mkdir "$RECOVERY_LOCK" 2>/dev/null; then
    local holder_pid=$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)
    if [ -n "$holder_pid" ] && [ -d "/proc/$holder_pid" ]; then
      log "恢复跳过: 上一实例仍在运行 (PID=$holder_pid)"
      return
    else
      # 僵尸锁: pid 缺失或进程已退出, 清理并接管
      log "检测到僵尸锁 (PID=${holder_pid:-无}), 清理并接管"
      rm -rf "$RECOVERY_LOCK" 2>/dev/null
      mkdir "$RECOVERY_LOCK" 2>/dev/null || { log "恢复跳过: 无法获取锁"; return; }
    fi
  fi
  echo "$$" > "$RECOVERY_LOCK/pid"
  # 写后验证: 防止并发实例刚删掉本锁目录并接管
  if [ "$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)" != "$$" ]; then
    log "锁竞争: 已被其他实例接管, 本次跳过"
    return
  fi

  # 冷却检查
  if [ -f "$STAMP" ]; then
    local elapsed=$(($(date +%s) - $(cat "$STAMP")))
    if [ $elapsed -lt $COOLDOWN ]; then
      log "恢复跳过: 冷却中 (${elapsed}s < ${COOLDOWN}s)"
      rm -rf "$RECOVERY_LOCK" 2>/dev/null
      return
    fi
  fi

  # 累加卡死次数
  local stuck=$(cat "$STUCK_COUNT" 2>/dev/null)
  stuck=$((stuck + 1))
  echo "$stuck" > "$STUCK_COUNT"

  # 计算冻结延迟
  local delay_min=$stuck
  [ $delay_min -gt $MAX_FREEZE_DELAY ] && delay_min=$MAX_FREEZE_DELAY
  local delay_sec=$((delay_min * 60))
  log "第 ${stuck} 次卡死，冻结延迟 = ${delay_min} 分钟 (${delay_sec}s)"

  # 步骤1: 解冻 logd
  if is_frozen; then
    unfreeze_logd
    sleep 2
  else
    log "logd 已解冻，跳过解冻步骤"
  fi

  # 步骤2: 重启 Scene
  restart_scene_daemon

  # 步骤3: 等待守护进程出现
  for i in $(seq 1 12); do
    check_daemon_process && break
    sleep 5
  done

  if ! check_daemon_process; then
    log "===== 恢复失败: 守护进程未出现 ====="
    rm -rf "$RECOVERY_LOCK" 2>/dev/null
    return
  fi
  log "守护进程已恢复"

  # 步骤4: 渐进等待
  log "等待 ${delay_min} 分钟后冻结 logd..."
  sleep "$delay_sec"

  # 步骤5: 冻结 logd
  local logd_pid=$(get_logd_pid)
  if [ -n "$logd_pid" ]; then
    freeze_logd "$logd_pid"
    log "===== 恢复完成 (延迟${delay_min}分钟) ====="
  else
    log "===== 恢复完成但 logd 未找到 ====="
  fi

  date +%s > "$STAMP"
  rm -rf "$RECOVERY_LOCK" 2>/dev/null
}

# ========== 卡死计数复位 ==========
reset_stuck_on_normal() {
  local normal=$(cat "$NORMAL_COUNT" 2>/dev/null)
  normal=$((normal + 1))
  echo "$normal" > "$NORMAL_COUNT"

  if [ "$normal" -ge "$RESET_THRESHOLD" ]; then
    local old_stuck=$(cat "$STUCK_COUNT" 2>/dev/null)
    if [ -n "$old_stuck" ] && [ "$old_stuck" -gt 0 ]; then
      log_info "连续正常 ${RESET_THRESHOLD} 次，复位卡死计数 (之前=$old_stuck)"
      echo 0 > "$STUCK_COUNT"
    fi
    echo 0 > "$NORMAL_COUNT"
  fi
}

# ========== 单次检查（由 crond 定时调用） ==========
check_once() {
  # 检测屏幕状态
  if is_screen_on; then
    SCREEN="亮屏"
  else
    SCREEN="息屏"
  fi

  # 息屏与亮屏的异常处理逻辑一致，仅在息屏跳过亮屏特有逻辑（已无文件监控，逻辑已等同）
  if is_scene_normal; then
    # 正常: 累积复位计数
    reset_stuck_on_normal
  else
    # 异常: 复位正常计数 + 执行恢复
    echo 0 > "$NORMAL_COUNT"
    local stuck=$(cat "$STUCK_COUNT" 2>/dev/null || echo 0)
    log "── [$SCREEN] 异常 · 累计卡死=${stuck}次 · logd=$(is_frozen && echo '已冻结' || echo '未冻结') ──"
    do_recovery
  fi
}

# ========== 服务启动流程 ==========
start_service() {
  Wait_until_login
  check_running
  log_clear "service.sh 启动 (PID=$$)"
  log "MODDIR=$MODDIR"
  log "cgroup路径=$CGPATH"
  log "亮屏间隔=${MONITOR_INTERVAL_ON}s | 熄屏间隔=${MONITOR_INTERVAL_OFF}s | 冷却=${COOLDOWN}s"

  # 初始化卡死计数
  echo 0 > "$STUCK_COUNT"
  echo 0 > "$NORMAL_COUNT"
  log "卡死计数已清零"

  # 获取 logd PID
  LOGD_PID=$(get_logd_pid)
  log "logd PID=$LOGD_PID"
  [ -z "$LOGD_PID" ] && { log "错误: logd 未运行, 退出"; exit 0; }

  # 等待 Scene 守护进程
  if pm list packages 2>/dev/null | grep -q "$SCENE_PKG"; then
    log "Scene 已安装，等待 $DAEMON_NAME..."
    for i in $(seq 1 24); do
      check_daemon_process && break
      sleep 5
    done
    if check_daemon_process; then
      log "Scene 守护进程已就绪"
    else
      log "警告: Scene 守护进程等待超时"
    fi
    sleep 5
  else
    log "Scene 未安装，跳过守护进程等待"
  fi

  # 创建 cgroup v2 并冻结 logd
  log "===== cgroup v2 设置 ====="
  freeze_logd "$LOGD_PID"

  # ========== 启动 crond 定时任务 ==========
  log "===== 启动 crond 定时任务 ====="

  # 设置 busybox crond 路径
  CROND_BIN=""
  if [[ -f "/data/adb/magisk" ]] || [[ -f "/data/adb/magiskpolicy" ]]; then
    CROND_BIN="$(magisk --path)/.magisk/busybox/crond"
  elif [[ -f "/data/adb/ksud" ]]; then
    CROND_BIN="/data/adb/busybox/crond"
  fi

  # fallback: 遍历常见 busybox 路径
  if [ -z "$CROND_BIN" ] || [ ! -f "$CROND_BIN" ]; then
    for p in /data/adb/busybox/crond /system/bin/crond /system/xbin/crond; do
      [ -f "$p" ] && { CROND_BIN="$p"; break; }
    done
  fi

  # 首次执行检查（crond 不可用或正常启动后都会执行一次）
  run_first_check() {
    log "===== 首次执行检查 ====="
    sh "$MODDIR/cron_check.sh" &
    log "首次检查已启动 (PID=$!)"
  }

  if [ -z "$CROND_BIN" ] || [ ! -f "$CROND_BIN" ]; then
    log "错误: 找不到 crond 二进制文件，跳过 crond 启动"
    run_first_check
    return
  fi

  # 创建 cron.d 目录
  mkdir -p "$MODDIR/cron.d"

  # 创建 cron 任务文件
  echo "* * * * * $MODDIR/cron_check.sh" > "$MODDIR/cron.d/root"

  # 设置执行权限
  chmod 755 "$MODDIR/cron_check.sh" 2>/dev/null
  
  # 显示 cron.d/root 内容
  log "cron.d/root 内容: $(cat "$MODDIR/cron.d/root" 2>/dev/null)"
  
  # 启动 crond
  "$CROND_BIN" -c "$MODDIR/cron.d" &
  CROND_PID=$!
  sleep 1
  log "crond 已启动 (PID=$CROND_PID)"

  # 检查 crond 是否运行 (pidof 比 pgrep 可靠)
  if pidof crond >/dev/null; then
    log "crond 运行正常"
  else
    log "错误: crond 启动失败，仅依赖首次检查"
  fi

  # 首次执行检查
  run_first_check
}
