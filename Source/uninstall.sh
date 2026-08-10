#!/system/bin/sh
# ======================================================
#  uninstall.sh - 模块卸载时清理
# ======================================================

MODDIR=${0%/*}

# ========== 加载函数库（含全部常量） ==========
. "$MODDIR/lib_core.sh"

LEGACY_PID="/data/local/tmp/logd_monitor.pid"
OLD_LOG="/data/local/tmp/scene_recovery.log"

log() {
  echo "[$(date '+%y/%m/%d %H:%M')] | [uninstall] $*" >> "$LOG_FILE" 2>/dev/null
}

log "===== uninstall.sh 开始清理 ====="

# 1. 解冻 logd
if is_frozen; then
  log "解冻 logd..."
  echo 0 > "$FREEZEFILE" 2>/dev/null
  pid=$(get_logd_pid)
  [ -n "$pid" ] && echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  log "logd 已解冻"
else
  log "logd 未冻结，跳过"
fi
rmdir "$CGPATH" 2>/dev/null

# 2. 停止 crond
log "停止 crond..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "crond.*$MODDIR/cron.d" 2>/dev/null
  log "crond pkill 已执行"
else
  for pid in $(ps -ef | grep "crond.*$MODDIR/cron.d" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log "crond kill PID=$pid"
  done
fi

# 3. 终止监控进程（service.sh 与正在运行的 cron_check/recovery）
log "终止监控进程..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "$MODDIR/cron_check.sh" 2>/dev/null
  pkill -f "freeze_logd_switch.*service.sh" 2>/dev/null
  pkill -f "$MODDIR/service.sh" 2>/dev/null
  log "pkill 已执行"
else
  for pid in $(ps -ef | grep -E "$MODDIR/(cron_check|service)\.sh" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log "kill PID=$pid"
  done
fi

# 4. 清理临时文件
rm -f "$STAMP" "$STUCK_COUNT" "$NORMAL_COUNT" "$PID_FILE" "$LEGACY_PID" "$OLD_LOG"
rm -f /data/local/tmp/freeze_action.log /data/local/tmp/freeze_install.log
rm -rf "$RECOVERY_LOCK" 2>/dev/null
log "临时文件已清理"

log "===== uninstall.sh 清理完成 ====="
