#!/system/bin/sh
# ======================================================
#  action.sh - Magisk 操作按钮：手动切换 logd 冻结/解冻
# ======================================================
#  注意：Magisk 在主线程同步执行此脚本，任何耗时操作都会导致 UI 卡顿。
#  因此日志写 /data/local/tmp（tmpfs，比 sdcardfs 快得多），
#  且 mkdir 只在初始化时执行一次。

MODDIR=${0%/*}
PROPFILE="$MODDIR/module.prop"
CGPATH=/sys/fs/cgroup/logd_frozen
FREEZEFILE="$CGPATH/cgroup.freeze"

# 日志初始化（一次性，不在 log 函数内重复 mkdir）
LOG_DIR="/data/local/tmp"
LOG_FILE="$LOG_DIR/freeze_action.log"

# log — 精简版，无 mkdir，date 只调用一次
log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

# 写入启动标记（用 > 截断旧日志）
echo "[$(date '+%y/%m/%d %H:%M:%S')] action 开始" > "$LOG_FILE"

# 核心操作 —— 全部在 tmpfs/cgroupfs 上，无 IO 瓶颈
LOGD_PID=$(pidof logd | awk '{print $1}')
[ -z "$LOGD_PID" ] && { echo "logd 进程未运行"; log "失败: logd 未运行"; exit 1; }

# 确保 cgroup 存在
if [ ! -d "$CGPATH" ]; then
  mkdir -p "$CGPATH"
  echo "+freezer" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null
  echo "$LOGD_PID" > "$CGPATH/cgroup.procs"
fi

# 读取 → 切换 → 写回（三步都是内存文件系统操作，极快）
STATE=$(cat "$FREEZEFILE" 2>/dev/null)
[ -z "$STATE" ] && STATE=0

if [ "$STATE" = "1" ]; then
  echo 0 > "$FREEZEFILE"
  echo "$LOGD_PID" > /sys/fs/cgroup/cgroup.procs 2>/dev/null
  rmdir "$CGPATH" 2>/dev/null
  sed -i "s/^description=.*/description=logd 已解冻 | 点击按钮冻结/" "$PROPFILE"
  echo "logd 已解冻"
  log "解冻完成"
else
  echo "$LOGD_PID" > "$CGPATH/cgroup.procs" 2>/dev/null
  echo 1 > "$FREEZEFILE"
  sed -i "s/^description=.*/description=logd 已冻结 | 点击按钮解冻/" "$PROPFILE"
  echo "logd 已冻结"
  log "冻结完成"
fi
