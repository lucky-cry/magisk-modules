#!/system/bin/sh
# ======================================================
#  action.sh - Magisk 操作按钮：手动切换 logd 冻结/解冻
# ======================================================
#  注意：Magisk 在主线程同步执行此脚本，任何耗时操作都会导致 UI 卡顿。
#  因此本脚本日志写 /data/local/tmp（tmpfs），避免 sdcardfs 阻塞。

MODDIR=${0%/*}

# ========== 加载函数库（含全部常量与冻结/解冻逻辑） ==========
. "$MODDIR/lib_core.sh"

# action 专用日志（tmpfs）
ACTION_LOG="/data/local/tmp/freeze_action.log"

log_action() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$ACTION_LOG"
}

# 写入启动标记（用 > 截断旧日志）
echo "[$(date '+%y/%m/%d %H:%M:%S')] action 开始" > "$ACTION_LOG"

# 核心操作 —— 全部在 tmpfs/cgroupfs 上，无 IO 瓶颈
LOGD_PID=$(get_logd_pid)
if [ -z "$LOGD_PID" ]; then
  echo "logd 进程未运行"
  log_action "失败: logd 未运行"
  exit 1
fi

# 读取 → 切换 → 写回（三步都是内存文件系统操作，极快）
if is_frozen; then
  unfreeze_logd
  echo "logd 已解冻"
  log_action "解冻完成"
else
  if freeze_logd "$LOGD_PID"; then
    echo "logd 已冻结"
    log_action "冻结完成"
  else
    echo "冻结失败（设备可能不支持 cgroup v2 freezer），请查看模块日志"
    log_action "失败: 冻结未生效"
  fi
fi
