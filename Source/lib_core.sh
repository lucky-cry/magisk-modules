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
LOG_MAX_SIZE=524288          # 日志超过 512KB 自动轮转(旧日志保留 .old)
LOG_LEVEL="info"             # debug=详细日志, 其他值只记录 info/error
MAX_DAEMON_COUNT=3            # scene-daemon 进程数超过该值判定异常堆积
DAEMON_WAIT_RETRIES=12        # 恢复流程中等待守护进程出现的轮询次数
STARTUP_WAIT_RETRIES=24       # 启动流程等待守护进程的轮询次数
POLL_INTERVAL=5               # 进程/挂载轮询间隔(秒)
UNFREEZE_SETTLE=2             # 解冻后等待 logd 恢复调度(秒)
RESTART_SETTLE=3              # 重启脚本执行后的缓冲等待(秒)
CROND_CHECK_RETRIES=3         # crond 启动检测重试次数
CROND_CHECK_INTERVAL=1        # crond 启动检测重试间隔(秒)
LOGIN_TIMEOUT=300             # 等待解锁/存储挂载的超时上限(秒)

# 若安装阶段部署了模块 busybox，则优先使用（customize.sh 会创建该目录）
[ -d "$MODDIR/busybox" ] && export PATH="$MODDIR/busybox:$PATH"

# ========== 等待用户解锁设备 ==========
Wait_until_login() {
  local waited=0

  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    waited=$((waited + POLL_INTERVAL))
    if [ "$waited" -ge "$LOGIN_TIMEOUT" ]; then
      log_warn "等待 sys.boot_completed 超时, 降级继续"
      return
    fi
    sleep "$POLL_INTERVAL"
  done

  waited=0
  until [ -d /sdcard/Android ]; do
    waited=$((waited + POLL_INTERVAL))
    if [ "$waited" -ge "$LOGIN_TIMEOUT" ]; then
      log_warn "等待 /sdcard 挂载超时, 降级继续"
      return
    fi
    sleep "$POLL_INTERVAL"
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
  # 大小轮转: 超限后旧日志保留一份 .old 再开新文件, 避免历史日志全部丢失
  local size=$(stat -c %s "$LOG_FILE" 2>/dev/null)
  if [ -n "$size" ] && [ "$size" -gt "$LOG_MAX_SIZE" ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
    # mv 失败(文件仍在)则跳过标记, 避免反复重试
    [ -f "$LOG_FILE" ] && return 0
    log "日志超限已轮转, 旧日志保留于 $LOG_FILE.old"
  fi
}

log_debug() {
  [ "$LOG_LEVEL" = "debug" ] && { log "DEBUG: $*"; return; }
  # 静默模式: 连续 5 次正常后暂停每分钟日志; 出现异常会自动恢复
  [ "$(cat "$LOG_QUIET_FILE" 2>/dev/null)" = "1" ] && return
  log "DEBUG: $*"
}
log_info()  { log "INFO: $*"; }
log_warn()  { log "WARN: $*"; }
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
    local old_pid cmdline
    read -r old_pid < "${PID_FILE}" 2>/dev/null
    if [ -n "${old_pid}" ] && [ -d "/proc/${old_pid}" ]; then
      # 同时校验 cmdline 含 service.sh 与本模块目录, 防止 PID 复用/其他模块误判
      cmdline=$(tr '\0' ' ' < "/proc/${old_pid}/cmdline" 2>/dev/null)
      case "$cmdline" in
        *"service.sh"*"$MODDIR"*|*"$MODDIR"*"service.sh"*)
          log_info "service.sh 已在运行 (PID: ${old_pid})，退出"
          exit 0
          ;;
      esac
    fi
    rm -f "${PID_FILE}" 2>/dev/null
    log_debug "过期 PID 文件已删除"
  fi
  echo $$ > "${PID_FILE}"
}

# ========== Scene 卡死判定 ==========
# 返回 0=正常, 1=异常
# 主判据: scene-daemon 进程数超过 MAX_DAEMON_COUNT 视为异常堆积
# 日志行数是历史信息，无法反映进程当前是否存活，仅作调试参考
is_scene_normal() {
  # 未安装 → 正常
  [ -d "/data/data/${SCENE_PKG}" ] || return 0

  local pid_count=$(pidof "$DAEMON_NAME" 2>/dev/null | wc -w)
  pid_count=${pid_count:-0}

  if [ "$pid_count" -gt "$MAX_DAEMON_COUNT" ]; then
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

# 解冻原语: 仅操作 cgroup（写回 0 → 移回根 cgroup → 删除子目录）
# 供 unfreeze_logd / freeze_logd 失败回滚 / uninstall 复用, 幂等可重复调用
unfreeze_cgroup() {
  [ -f "$FREEZEFILE" ] && echo 0 > "$FREEZEFILE" 2>/dev/null
  local pid="${1:-$(get_logd_pid)}"
  [ -n "$pid" ] && echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  rmdir "$CGPATH" 2>/dev/null
}

freeze_logd() {
  local pid="$1"
  local state
  mkdir -p "$CGPATH" 2>/dev/null
  echo "+freezer" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null
  if ! echo "$pid" > "$CGPATH/cgroup.procs" 2>/dev/null; then
    log_error "写入 cgroup.procs 失败"
    unfreeze_cgroup "$pid"
    return 1
  fi
  if ! echo 1 > "$FREEZEFILE" 2>/dev/null; then
    log_error "写入 cgroup.freeze 失败"
    unfreeze_cgroup "$pid"
    return 1
  fi
  # 回读验证冻结是否真正生效（只读一次复用）
  state=$(cat "$FREEZEFILE" 2>/dev/null)
  if [ "$state" != "1" ]; then
    log_error "freeze_logd: 冻结未生效 (cgroup.freeze=$state)"
    unfreeze_cgroup "$pid"
    return 1
  fi
  sed -i "s/^description=.*/description=logd 已冻结（循环监控） | 点击按钮解冻/" "$MODDIR/module.prop" 2>/dev/null
  log_info "freeze_logd: PID=$pid 已冻结, cgroup.freeze=$state, module.prop 已同步"
}

unfreeze_logd() {
  unfreeze_cgroup
  sed -i "s/^description=.*/description=logd 已解冻 | 点击按钮冻结/" "$MODDIR/module.prop" 2>/dev/null
  log_info "unfreeze_logd: logd 已解冻, cgroup子目录已清理, module.prop 已同步"
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
  sleep "$RESTART_SETTLE"
  return "$rc"
}

# ========== 计数/时间戳读取（防御空文件与脏数据） ==========
# tmpfs 可能被用户/系统清理, 空文件或脏内容会导致算术展开报错
read_count() {
  local val=$(cat "$1" 2>/dev/null)
  case "$val" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$val" ;;
  esac
}

# ========== 恢复流程（渐进式冻结延迟） ==========
do_recovery() {
  log_info "===== 开始 Scene 异常恢复 ====="

  # 互斥锁: 防止并发多个实例并行执行
  # 锁目录存在即锁定, 内含 pid 文件用于僵尸锁检测
  if ! mkdir "$RECOVERY_LOCK" 2>/dev/null; then
    local holder_pid=$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)
    if [ -n "$holder_pid" ] && [ -d "/proc/$holder_pid" ]; then
      log_debug "恢复跳过: 上一实例仍在运行 (PID=$holder_pid)"
      return
    else
      # 僵尸锁: pid 缺失或进程已退出, 清理并接管
      log_warn "检测到僵尸锁 (PID=${holder_pid:-无}), 清理并接管"
      rm -rf "$RECOVERY_LOCK" 2>/dev/null
      mkdir "$RECOVERY_LOCK" 2>/dev/null || { log_warn "恢复跳过: 无法获取锁"; return; }
    fi
  fi
  echo "$$" > "$RECOVERY_LOCK/pid"
  # 写后验证: 防止并发实例刚删掉本锁目录并接管
  if [ "$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)" != "$$" ]; then
    log_warn "锁竞争: 已被其他实例接管, 本次跳过"
    return
  fi

  # 获得锁后统一由 EXIT trap 释放, 消除分散的 rm 与遗漏路径
  # (kill -9 等无法执行 trap 的情况, 由僵尸锁检测兜底)
  trap 'rm -rf "$RECOVERY_LOCK" 2>/dev/null' EXIT

  # 冷却检查
  if [ -f "$STAMP" ]; then
    local stamp=$(read_count "$STAMP")
    local elapsed=$(($(date +%s) - stamp))
    if [ "$elapsed" -lt "$COOLDOWN" ]; then
      log_info "恢复跳过: 冷却中 (${elapsed}s < ${COOLDOWN}s)"
      return
    fi
  fi

  # 累加卡死次数
  local stuck=$(read_count "$STUCK_COUNT")
  stuck=$((stuck + 1))
  echo "$stuck" > "$STUCK_COUNT"

  # 计算冻结延迟
  local delay_min=$stuck
  [ $delay_min -gt $MAX_FREEZE_DELAY ] && delay_min=$MAX_FREEZE_DELAY
  local delay_sec=$((delay_min * 60))
  log_warn "第 ${stuck} 次卡死，冻结延迟 = ${delay_min} 分钟 (${delay_sec}s)"

  # 步骤1: 解冻 logd
  if is_frozen; then
    unfreeze_logd
    sleep "$UNFREEZE_SETTLE"
  else
    log_info "logd 已解冻，跳过解冻步骤"
  fi

  # 步骤2: 重启 Scene (失败提前退出, 避免空等 60 秒)
  if ! restart_scene_daemon; then
    log_error "===== 恢复失败: 重启脚本不可用 ====="
    return
  fi

  # 步骤3: 等待守护进程出现
  for i in $(seq 1 $DAEMON_WAIT_RETRIES); do
    check_daemon_process && break
    sleep "$POLL_INTERVAL"
  done

  if ! check_daemon_process; then
    log_error "===== 恢复失败: 守护进程未出现 ====="
    return
  fi
  log_info "守护进程已恢复"

  # 步骤4: 渐进等待
  log_info "等待 ${delay_min} 分钟后冻结 logd..."
  sleep "$delay_sec"

  # 步骤5: 冻结 logd
  local logd_pid=$(get_logd_pid)
  if [ -n "$logd_pid" ]; then
    freeze_logd "$logd_pid"
    log_info "===== 恢复完成 (延迟${delay_min}分钟) ====="
  else
    log_warn "===== 恢复完成但 logd 未找到 ====="
  fi

  date +%s > "$STAMP"
}

# ========== 恢复是否进行中 ==========
is_recovery_running() {
  [ -d "$RECOVERY_LOCK" ] || return 1
  local holder_pid=$(cat "$RECOVERY_LOCK/pid" 2>/dev/null)
  [ -n "$holder_pid" ] && [ -d "/proc/$holder_pid" ]
}

# ========== 卡死计数复位 ==========
reset_stuck_on_normal() {
  local normal=$(read_count "$NORMAL_COUNT")
  normal=$((normal + 1))
  # 计数封顶, 保持"已连续正常"状态用于日志静默判断
  [ "$normal" -gt "$RESET_THRESHOLD" ] && normal=$RESET_THRESHOLD
  echo "$normal" > "$NORMAL_COUNT"

  if [ "$normal" -ge "$RESET_THRESHOLD" ]; then
    local old_stuck=$(read_count "$STUCK_COUNT")
    if [ "$old_stuck" -gt 0 ]; then
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

# ========== 检查本模块 crond 实例 ==========
# crond 通常单实例: 其他 crond 已运行时本模块实例可能启动失败,
# 此时 pidof crond 仍为真, 必须按本模块 cron.d 目录匹配进程 cmdline
is_crond_running() {
  local pid_dir comm line
  for pid_dir in /proc/[0-9]*; do
    [ -r "$pid_dir/cmdline" ] || continue
    comm=$(cat "$pid_dir/comm" 2>/dev/null)
    [ "$comm" = "crond" ] || continue
    line=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null)
    case "$line" in
      *"$MODDIR/cron.d"*) return 0 ;;
    esac
  done
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
    local normal=$(read_count "$NORMAL_COUNT")
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
    log_warn "检测到 Scene 异常, 恢复每分钟详细日志, 开始恢复流程"
    ( do_recovery ) >/dev/null 2>&1 &
  fi
}

# ========== 服务启动流程 ==========
start_service() {
  Wait_until_login
  check_running
  log_clear "service.sh 启动 (PID=$$)"
  log_info "MODDIR=$MODDIR"
  log_info "cgroup路径=$CGPATH"
  log_info "冷却=${COOLDOWN}s | 日志级别=${LOG_LEVEL}"

  # cgroup 环境信息（仅 LOG_LEVEL=debug 时输出, 默认不打扰日志）
  log_debug "cgroup fs类型=$(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
  log_debug "cgroup.controllers=$(tr '\n' ' ' < /sys/fs/cgroup/cgroup.controllers 2>/dev/null)"

  # 初始化卡死计数
  echo 0 > "$STUCK_COUNT"
  echo 0 > "$NORMAL_COUNT"
  echo 0 > "$LOG_QUIET_FILE"
  log_info "卡死计数已清零"

  # 获取 logd PID
  LOGD_PID=$(get_logd_pid)
  log_info "logd PID=$LOGD_PID"
  [ -z "$LOGD_PID" ] && { log_error "logd 未运行, 退出"; exit 0; }

  # 等待 Scene 守护进程
  if [ -d "/data/data/$SCENE_PKG" ]; then
    log_info "Scene 已安装，等待 $DAEMON_NAME..."
    for i in $(seq 1 $STARTUP_WAIT_RETRIES); do
      check_daemon_process && break
      sleep "$POLL_INTERVAL"
    done
    if check_daemon_process; then
      log_info "Scene 守护进程已就绪"
    else
      log_warn "Scene 守护进程等待超时"
    fi
    sleep "$POLL_INTERVAL"
  else
    log_info "Scene 未安装，跳过守护进程等待"
  fi

  # 创建 cgroup v2 并冻结 logd
  log_info "===== cgroup v2 设置 ====="
  freeze_logd "$LOGD_PID"

  # ========== 启动 crond 定时任务 ==========
  log_info "===== 启动 crond 定时任务 ====="

  CROND_BIN=$(find_crond)

  # 首次执行检查（crond 不可用或正常启动后都会执行一次）
  run_first_check() {
    log_info "===== 首次执行检查 ====="
    sh "$MODDIR/cron_check.sh" &
    log_info "首次检查已启动 (PID=$!)"
  }

  if [ -z "$CROND_BIN" ]; then
    log_error "找不到 crond 二进制文件，跳过 crond 启动"
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
  log_info "cron.d/root 内容: $(cat "$MODDIR/cron.d/root" 2>/dev/null)"

  # 启动 crond
  "$CROND_BIN" -c "$MODDIR/cron.d" &
  CROND_PID=$!
  sleep "$CROND_CHECK_INTERVAL"
  log_info "crond 已启动 (PID=$CROND_PID)"

  # 检查本模块 crond 实例是否运行
  # 注意: 不能只凭 pidof crond(其他 crond 实例也会命中), 必须匹配本模块 cron.d 目录
  local crond_ok=0
  for i in $(seq 1 $CROND_CHECK_RETRIES); do
    if is_crond_running; then
      crond_ok=1
      break
    fi
    sleep "$CROND_CHECK_INTERVAL"
  done
  if [ "$crond_ok" = "1" ]; then
    log_info "crond 运行正常"
  else
    log_error "crond 启动失败(可能已有其他 crond 实例在运行), 仅依赖首次检查"
  fi

  # 首次执行检查
  run_first_check
}
