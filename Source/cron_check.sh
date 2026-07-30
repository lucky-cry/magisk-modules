#!/system/bin/sh
# ======================================================
#  cron_check.sh - 单次检查脚本（由 crond 定时调用）
#  替代原来的 loop.sh 无限循环
#  每次执行完自动退出，由 crond 定时重新调用
# ======================================================

MODDIR=${0%/*}

# ========== 全局常量 ==========
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

# ========== 加载函数库 ==========
. "$MODDIR/lib_core.sh"

# ========== 执行检查 ==========
check_once
