#!/bin/sh
# ======================================================
#  update_meta.sh - 模块元数据单一生成脚本
#  统一生成 update.json / version / changelog 版本头,
#  供 CI (build-module.yml / sync-to-gitee.yml) 与本地 sync.bat 共用,
#  消除三套重复维护逻辑导致的格式漂移。
#  用法: sh update_meta.sh [github|gitee]   (默认 github)
# ======================================================
set -e

TARGET="${1:-github}"
case "$TARGET" in
  github|gitee) ;;
  *) echo "用法: sh update_meta.sh [github|gitee]" >&2; exit 1 ;;
esac

# ---------- 从 module.prop 读取版本信息 ----------
MODULE_ID=$(sed -n 's/^id=//p' Source/module.prop)
MODULE_VERSION=$(sed -n 's/^version=//p' Source/module.prop)
MODULE_VERSIONCODE=$(sed -n 's/^versionCode=//p' Source/module.prop)

if [ -z "$MODULE_VERSION" ] || [ -z "$MODULE_VERSIONCODE" ]; then
  echo "[错误] 无法从 Source/module.prop 读取版本信息" >&2
  exit 1
fi

# ---------- 目标仓库地址 ----------
if [ "$TARGET" = "gitee" ]; then
  BASE_URL="https://gitee.com/lucky__cat/magisk-modules"
  CHANGELOG_URL="${BASE_URL}/raw/freeze_logd_switch/changelog"
else
  BASE_URL="https://github.com/lucky-cry/magisk-modules"
  CHANGELOG_URL="https://raw.githubusercontent.com/lucky-cry/magisk-modules/freeze_logd_switch/changelog"
fi

# ---------- 生成 version ----------
cat > version <<EOF
##update info
name=v${MODULE_VERSION}
version=${MODULE_VERSIONCODE}
EOF

# ---------- 生成 update.json ----------
cat > update.json <<EOF
{
  "version": "${MODULE_VERSION}",
  "versionCode": ${MODULE_VERSIONCODE},
  "zipUrl": "${BASE_URL}/releases/download/v${MODULE_VERSION}/${MODULE_ID}-${MODULE_VERSION}.zip",
  "changelog": "${CHANGELOG_URL}"
}
EOF

# ---------- changelog 版本头（首行缺失时补插, 避免重复插入） ----------
if ! head -n 1 changelog | grep -qx "v${MODULE_VERSION}"; then
  { echo "v${MODULE_VERSION}"; tail -n +2 changelog; } > changelog.tmp
  mv changelog.tmp changelog
fi

echo "update_meta.sh [${TARGET}]: v${MODULE_VERSION} (${MODULE_VERSIONCODE}) 已生成 update.json / version"
