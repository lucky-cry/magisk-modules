WHITELIST=/sdcard/Android/BATTERYOPT/电池优化白名单.prop

whitelist=$(cat "$WHITELIST" | grep -v '^#' | grep '^+' | sed 's/^+//')
whitelist=`pm list packages -3 | sed "s/package:/-/g"`"$whitelist"
dumpsys deviceidle whitelist $whitelist
