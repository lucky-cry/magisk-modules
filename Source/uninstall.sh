#!/system/bin/sh
# ======================================================
#  uninstall.sh - 模块卸载时清理
# ======================================================

MODDIR=${0%/*}

# ========== 加载函数库（含全部常量） ==========
. "$MODDIR/lib_core.sh"

LEGACY_PID="/data/local/tmp/logd_monitor.pid"
OLD_LOG="/data/local/tmp/scene_recovery.log"

# 卸载专用日志（区别于库函数 log, 避免同名覆盖）
log_uninstall() {
  echo "[$(date '+%y/%m/%d %H:%M')] | [uninstall] $*" >> "$LOG_FILE" 2>/dev/null
}

log_uninstall "===== uninstall.sh 开始清理 ====="

# 1. 解冻 logd（unfreeze_cgroup 幂等, 未冻结时仅兜底清理残留目录）
if is_frozen; then
  log_uninstall "解冻 logd..."
  unfreeze_cgroup
  log_uninstall "logd 已解冻"
else
  log_uninstall "logd 未冻结，跳过"
  unfreeze_cgroup
fi

# 2. 停止 crond
log_uninstall "停止 crond..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "crond.*$MODDIR/cron.d" 2>/dev/null
  log_uninstall "crond pkill 已执行"
else
  for pid in $(ps -ef | grep "crond.*$MODDIR/cron.d" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log_uninstall "crond kill PID=$pid"
  done
fi

# 3. 终止监控进程（service.sh 与正在运行的 cron_check/recovery）
log_uninstall "终止监控进程..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f "$MODDIR/cron_check.sh" 2>/dev/null
  pkill -f "freeze_logd_switch.*service.sh" 2>/dev/null
  pkill -f "$MODDIR/service.sh" 2>/dev/null
  log_uninstall "pkill 已执行"
else
  for pid in $(ps -ef | grep -E "$MODDIR/(cron_check|service)\.sh" | grep -v grep | awk '{print $2}'); do
    kill "$pid" 2>/dev/null
    log_uninstall "kill PID=$pid"
  done
fi

# 4. 清理临时文件
rm -f "$STAMP" "$STUCK_COUNT" "$NORMAL_COUNT" "$LOG_QUIET_FILE" "$PID_FILE" "$LEGACY_PID" "$OLD_LOG"
rm -f /data/local/tmp/freeze_action.log /data/local/tmp/freeze_install.log
rm -rf "$RECOVERY_LOCK" 2>/dev/null
log_uninstall "临时文件已清理"

log_uninstall "===== uninstall.sh 清理完成 ====="
