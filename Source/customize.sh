#!/bin/sh
# ======================================================
#  customize.sh - 模块安装阶段的自定义脚本
# ======================================================
#  功能说明：
#    Magisk 刷入模块时，在解压文件之后、完成安装之前调用此脚本。
#    本脚本负责部署 busybox 工具集，lib_core.sh 启动时会把该目录加入 PATH。
#
#  日志输出：
#    安装过程通过 ui_print 显示在 Magisk 刷入界面
#    安装日志也会写入 /data/local/tmp/freeze_install.log
#   （存储路径在安装阶段可能尚未挂载，因此使用 /data/local/tmp）
# ======================================================

# ---------- 变量定义 ----------
MODDIR=${0%/*}                                  # 模块目录路径（Magisk 自动注入）
busyboxdir=$MODPATH/busybox                     # busybox 符号链接安装目标目录
magiskbusybox=/data/adb/magisk/busybox          # Magisk 自带的 busybox 二进制文件
# 查找系统中 Magisk 提供的 busybox（排除模块目录中可能存在的副本）
kernelbusybox=`find /data/adb/ -iname "busybox" -type f | sed '/modules/d' | head -n 1`

# 安装日志（安装阶段 /sdcard 可能未挂载，写入 /data/local/tmp）
INSTALL_LOG="/data/local/tmp/freeze_install.log"

#
# install_log - 向安装日志追加带时间戳的行，同时 ui_print 显示在刷入界面
#
install_log() {
  echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$INSTALL_LOG" 2>/dev/null
  echo "$1"  # 同时输出到 ui_print 通道
}

#
# install_busybox - 用指定 busybox 二进制部署符号链接到模块目录
#
install_busybox() {
  local src="$1"
  install_log "使用 busybox: ${src}"
  mkdir -p "${busyboxdir}"
  ui_print "－ 安装 busybox 中……"
  if "${src}" --install -s "${busyboxdir}"; then
    install_log "busybox --install -s 成功"
    ui_print "－ 完成！"
  else
    install_log "错误: busybox --install -s 失败！"
    abort "－ 错误！"
  fi
}

install_log "===== customize.sh 开始执行 ====="
install_log "MODDIR=$MODDIR"
install_log "MODPATH=$MODPATH"
install_log "magiskbusybox=$magiskbusybox"
install_log "kernelbusybox=$kernelbusybox"

# ---------- 部署 busybox ----------
# 策略：优先 Magisk 自带 busybox → 系统内置 busybox → 报错中止
# 部署后 lib_core.sh 会自动将该目录加入 PATH

if test -f "${magiskbusybox}"; then
  # 情况1：使用 Magisk 自带的 busybox
  install_busybox "${magiskbusybox}"

elif test -f "${kernelbusybox}"; then
  # 情况2：使用非 Magisk 路径下找到的 busybox
  install_busybox "${kernelbusybox}"

else
  # 情况3：未找到任何 busybox
  install_log "错误: 未找到任何 busybox 二进制文件！"
  install_log "  检查路径: $magiskbusybox (不存在)"
  install_log "  搜索路径: /data/adb/ (未找到)"
  abort "－ 您的magisk busybox 怎么不见了？"
fi

# ---------- 显示安装成功信息 ----------
install_log "===== customize.sh 完成 ====="
ui_print " "
ui_print "        ✅ Frozen logd              "
ui_print "            By 懒猫"
ui_print "            请重启使用"
