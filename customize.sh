#!/system/bin/sh
# 请不要硬编码 /magisk/modname/... ; 请使用 $MODPATH/...
# 这将使你的脚本更加兼容，即使Magisk在未来改变了它的挂载点

# 设置权限
set_perm_recursive $MODPATH 0 0 0755 0644

# 设置字体文件权限
set_perm_recursive $MODPATH/system/fonts 0 0 0755 0644

ui_print "- 字体模块安装完成"
ui_print "- 请重启设备以应用新字体"
