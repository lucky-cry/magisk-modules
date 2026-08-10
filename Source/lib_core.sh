#!/system/bin/sh
# ======================================================
#  lib_core.sh - 函数库（日志 / 检测 / cgroup / 恢复）
#  被 service.sh / cron_check.sh / action.sh / uninstall.sh 加载
#  所有常量在此单点维护，修改后重启 service 即可生效
# ======================================================

# ========== 全局常量（单点维护） ==========
CGPATH=/sys/fs/cgroup/logd_frozen
FREEZEFILE="$CGPATH/cgroup.freeze"
SCENE_PKG="com.omarea.vtools"
DAEMON_NAME="scene-daemon"
COOLDOWN=60
STAMP="/data/local/tmp/scene_last_recovery"
STUCK_COUNT="/data/local/tmp/scene_stuck_count"
NORMAL_COUNT="/data/local/tmp/scene_normal_count"
RESET_THRESHOLD=5
MAX_FREEZE_DELAY=5
LOG_DIR="/storage/emulated/0/Android/Freeze_logd"
LOG_FILE="$LOG_DIR/log.md"
PID_FILE="/data/local/tmp/freeze_logd_service.pid"
RECOVERY_LOCK="/data/local/tmp/freeze_recovery_lock"
LOG_QUIET_FILE="/data/local/tmp/freeze_log_quiet"   # 1=静默模式(暂停每分钟详细日志)
LOG_MAX_SIZE=524288          # 日志超过 512KB 自动轮转
LOG_LEVEL="info"             # debug=详细日志, 其他值只记录 info/error

# 若安装阶段部署了模块 busybox，则优先使用（customize.sh 会创建该目录）
[ -d "$MODDIR/busybox" ] && export PATH="$MODDIR/busybox:$PATH"

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
  mkdir -p "$LOG_DIR" 2>/dev/null
  echo "[$(date '+%y/%m/%d %H:%M:%S')] | $*" >> "$LOG_FILE" 2>/dev/null
  # 大小轮转（stat 只读元数据，开销极小）
  local size=$(stat -c %s "$LOG_FILE" 2>/dev/null)
  if [ -n "$size" ] && [ "$size" -gt "$LOG_MAX_SIZE" ]; then
    log_clear "日志超限已轮转"
  fi
}

log_debug() {
  [ "$LOG_LEVEL" = "debug" ] && { log "DEBUG: $*"; return; }
  # 静默模式: 连续 5 次正常后暂停每分钟日志; 出现异常会自动恢复
  [ "$(cat "$LOG_QUIET_FILE" 2>/dev/null)" = "1" ] && return
  log "DEBUG: $*"
}
log_info()  { log "INFO: $*"; }
log_error() { log "ERROR: $*"; }

# ========== 进程检测 ==========
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

# ========== Scene 卡死判定 ==========
# 返回 0=正常, 1=异常
# 主判据: scene-daemon 进程数 > 3 视为异常堆积
# 日志行数是历史信息，无法反映进程当前是否存活，仅作调试参考
is_scene_normal() {
  # 未安装 → 正常
  [ -d "/data/data/${SCENE_PKG}" ] || return 0

  local pid_count=$(pidof "$DAEMON_NAME" 2>/dev/null | wc -w)
  pid_count=${pid_count:-0}

  if [ "$pid_count" -gt 3 ]; then
    log_debug "Scene 异常: 进程数=$pid_count"
    return 1
  fi

  log_debug "Scene 正常: 进程数=$pid_count"
  return 0
}

# ========== cgroup 冻结/解冻 ==========
is_frozen() {
  [ -f "$FREEZEFILE" ] && [ "$(cat "$FREEZEFILE")" = "1" ]
}

freeze_logd() {
  local pid="$1"
  mkdir -p "$CGPATH" 2>/dev/null
  echo "+freezer" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null
  echo "$pid" > "$CGPATH/cgroup.procs" 2>/dev/null || { log_error "写入 cgroup.procs 失败"; return 1; }
  echo 1 > "$FREEZEFILE" 2>/dev/null || { log_error "写入 cgroup.freeze 失败"; return 1; }
  # 回读验证冻结是否真正生效
  if [ "$(cat "$FREEZEFILE" 2>/dev/null)" != "1" ]; then
    log_error "freeze_logd: 冻结未生效 (cgroup.freeze=$(cat "$FREEZEFILE" 2>/dev/null))"
    return 1
  fi
  sed -i "s/^description=.*/description=logd 已冻结（循环监控） | 点击按钮解冻/" "$MODDIR/module.prop" 2>/dev/null
  log "freeze_logd: PID=$pid 已冻结, cgroup.freeze=$(cat "$FREEZEFILE" 2>/dev/null), module.prop 已同步"
}

unfreeze_logd() {
  [ -f "$FREEZEFILE" ] && echo 0 > "$FREEZEFILE" 2>/dev/null
  local pid=$(get_logd_pid)
  [ -n "$pid" ] && echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  rmdir "$CGPATH" 2>/dev/null
  sed -i "s/^description=.*/description=logd 已解冻 | 点击按钮冻结/" "$MODDIR/module.prop" 2>/dev/null
  log "unfreeze_logd: logd 已解冻, cgroup子目录已清理, module.prop 已同步"
}

# ========== 冻结完整性校验 ==========
# logd 重启后 cgroup.procs 里的旧 PID 会失效，检测到漂移即重新冻结
ensure_logd_frozen() {
  local pid=$(get_logd_pid)
  [ -n "$pid" ] || { log_error "ensure_logd_frozen: logd 未运行"; return 1; }
  if is_frozen && grep -qw "$pid" "$CGPATH/cgroup.procs" 2>/dev/null; then
    return 0
  fi
  log_info "检测到冻结漂移, 重新冻结 logd (PID=$pid)"
  freeze_logd "$pid"
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
  sh "$scene_restart" >/dev/null 2>&1
  local rc=$?
  log_info "重启脚本退出码=$rc"
  sleep 3
}

# ========== 恢复流程（渐进式冻结延迟） ==========
do_recovery() {
  log "===== 开始 Scene 异常恢复 ====="

  # 互斥锁: 防止并发多个实例并行执行
  # 锁目录存在即锁定, 内含 pid 文件用于僵尸锁检测
  if ! mkdir "$RECOVERY_LOCK" 2>/dev/null; then
    local holder_pid=$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)
    if [ -n "$holder_pid" ] && [ -d "/proc/$holder_pid" ]; then
      log_debug "恢复跳过: 上一实例仍在运行 (PID=$holder_pid)"
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

# ========== 恢复是否进行中 ==========
is_recovery_running() {
  [ -d "$RECOVERY_LOCK" ] || return 1
  local holder_pid=$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)
  [ -n "$holder_pid" ] && [ -d "/proc/$holder_pid" ]
}

# ========== 卡死计数复位 ==========
reset_stuck_on_normal() {
  local normal=$(cat "$NORMAL_COUNT" 2>/dev/null)
  normal=$((normal + 1))
  # 计数封顶, 保持"已连续正常"状态用于日志静默判断
  [ "$normal" -gt "$RESET_THRESHOLD" ] && normal=$RESET_THRESHOLD
  echo "$normal" > "$NORMAL_COUNT"

  if [ "$normal" -ge "$RESET_THRESHOLD" ]; then
    local old_stuck=$(cat "$STUCK_COUNT" 2>/dev/null)
    if [ -n "$old_stuck" ] && [ "$old_stuck" -gt 0 ]; then
      log_info "连续正常 ${RESET_THRESHOLD} 次，复位卡死计数 (之前=$old_stuck)"
      echo 0 > "$STUCK_COUNT"
    fi
  fi
}

# ========== 查找 crond 二进制 ==========
# 兼容 Magisk / KernelSU / 系统自带
find_crond() {
  local p=""
  if command -v magisk >/dev/null 2>&1; then
    p="$(magisk --path 2>/dev/null)/.magisk/busybox/crond"
    [ -f "$p" ] && { echo "$p"; return 0; }
  fi
  for p in \
    /data/adb/ksu/bin/crond \
    /data/adb/busybox/crond \
    /system/bin/crond \
    /system/xbin/crond; do
    if [ -f "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  if command -v crond >/dev/null 2>&1; then
    command -v crond
    return 0
  fi
  return 1
}

# ========== 单次检查（由 crond 定时调用） ==========
check_once() {
  # 恢复进行中则跳过本轮, 避免计数器竞争与日志噪音
  if is_recovery_running; then
    log_debug "恢复流程进行中, 跳过本轮检查"
    return
  fi

  # 冻结完整性: logd 重启后自动重新冻结
  ensure_logd_frozen

  if is_scene_normal; then
    # 正常: 连续 RESET_THRESHOLD 次后进入静默模式, 暂停每分钟详细日志
    local normal=$(cat "$NORMAL_COUNT" 2>/dev/null)
    normal=${normal:-0}
    if [ "$normal" -ge "$RESET_THRESHOLD" ]; then
      echo 1 > "$LOG_QUIET_FILE"
    else
      echo 0 > "$LOG_QUIET_FILE"
    fi
    reset_stuck_on_normal
  else
    # 异常: 复位计数 + 恢复详细日志 + 后台执行恢复（不长时间占用 crond 槽位）
    echo 0 > "$NORMAL_COUNT"
    echo 0 > "$LOG_QUIET_FILE"
    log "检测到 Scene 异常, 恢复每分钟详细日志, 开始恢复流程"
    ( do_recovery ) >/dev/null 2>&1 &
  fi
}

# ========== 服务启动流程 ==========
start_service() {
  Wait_until_login
  check_running
  log_clear "service.sh 启动 (PID=$$)"
  log "MODDIR=$MODDIR"
  log "cgroup路径=$CGPATH"
  log "冷却=${COOLDOWN}s | 日志级别=${LOG_LEVEL}"

  # cgroup 环境信息（仅 LOG_LEVEL=debug 时输出, 默认不打扰日志）
  log_debug "cgroup fs类型=$(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
  log_debug "cgroup.controllers=$(tr '\n' ' ' < /sys/fs/cgroup/cgroup.controllers 2>/dev/null)"

  # 初始化卡死计数
  echo 0 > "$STUCK_COUNT"
  echo 0 > "$NORMAL_COUNT"
  echo 0 > "$LOG_QUIET_FILE"
  log "卡死计数已清零"

  # 获取 logd PID
  LOGD_PID=$(get_logd_pid)
  log "logd PID=$LOGD_PID"
  [ -z "$LOGD_PID" ] && { log "错误: logd 未运行, 退出"; exit 0; }

  # 等待 Scene 守护进程
  if [ -d "/data/data/$SCENE_PKG" ]; then
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

  CROND_BIN=$(find_crond)

  # 首次执行检查（crond 不可用或正常启动后都会执行一次）
  run_first_check() {
    log "===== 首次执行检查 ====="
    sh "$MODDIR/cron_check.sh" &
    log "首次检查已启动 (PID=$!)"
  }

  if [ -z "$CROND_BIN" ]; then
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
