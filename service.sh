#!/system/bin/sh
# ======================================================
#  service.sh - Magisk 启动脚本
#  所有逻辑已融合到 lib_core.sh 中
#  修改 lib_core.sh 后重启 service 即可生效
# ======================================================

MODDIR=${0%/*}

# ========== 全局常量 ==========
CGPATH=/sys/fs/cgroup/logd_frozen
FREEZEFILE="$CGPATH/cgroup.freeze"
SCENE_PKG="com.omarea.vtools"
DAEMON_NAME="scene-daemon"
MONITOR_INTERVAL_ON=30
MONITOR_INTERVAL_OFF=60
COOLDOWN=60
STAMP="/data/local/tmp/scene_last_recovery"
STUCK_COUNT="/data/local/tmp/scene_stuck_count"
NORMAL_COUNT="/data/local/tmp/scene_normal_count"
RESET_THRESHOLD=5
MAX_FREEZE_DELAY=5
LOG_DIR="/storage/emulated/0/Android/Freeze_logd"
LOG_FILE="$LOG_DIR/log.md"
PID_FILE="/data/local/tmp/freeze_logd_service.pid"

# ========== 加载函数库 ==========
. "$MODDIR/lib_core.sh"

# ========== 启动服务 ==========
start_service
