#!/system/bin/sh
# ======================================================
#  uninstall.sh - 模块卸载时清理
# ======================================================

MODDIR=${0%/*}
CGPATH=/sys/fs/cgroup/logd_frozen
FREEZEFILE="$CGPATH/cgroup.freeze"
STAMP="/data/local/tmp/scene_last_recovery"
LEGACY_PID="/data/local/tmp/logd_monitor.pid"
OLD_LOG="/data/local/tmp/scene_recovery.log"
LOG_DIR="/storage/emulated/0/Android/Freeze_logd"
LOG_FILE="$LOG_DIR/log.md"

log() {
  echo "[$(date '+%y/%m/%d %H:%M')] | [uninstall] $*" >> "$LOG_FILE" 2>/dev/null
}

log "===== uninstall.sh 开始清理 ====="

# 1. 解冻 logd
if [ -f "$FREEZEFILE" ] && [ "$(cat "$FREEZEFILE")" = "1" ]; then
  log "解冻 logd..."
  echo 0 > "$FREEZEFILE"
  pid=$(pidof logd | awk '{print $1}')
  [ -n "$pid" ] && echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  rmdir "$CGPATH" 2>/dev/null
  log "logd 已解冻"
else
  log "logd 未冻结，跳过"
fi

# 2. 停止 crond
log "停止 crond..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "crond.*$MODDIR/cron.d"
  log "crond pkill 已执行"
else
  for pid in $(ps -ef | grep "crond.*$MODDIR/cron.d" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log "crond kill PID=$pid"
  done
fi

# 3. 终止 service.sh 监控进程
log "终止 service.sh..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "freeze_logd_switch.*service.sh"
  pkill -f "$MODDIR/service.sh"
  log "pkill 已执行"
else
  for pid in $(ps -ef | grep "$MODDIR/service.sh" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log "kill PID=$pid"
  done
fi

# 4. 清理临时文件
rm -f "$STAMP" "$LEGACY_PID" "$OLD_LOG"
log "临时文件已清理"

log "===== uninstall.sh 清理完成 ====="
