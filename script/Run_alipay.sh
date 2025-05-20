MODDIR=${0%/*}
START_ALIPAY_LOG="/sdcard/Android/start_alipay/log.md"
WORK_LIST="/sdcard/Android/start_alipay/勿扰名单.prop"

# Create log file if it doesn't exist
if [ ! -f $START_ALIPAY_LOG ]; then
    mkdir sdcard/Android/start_alipay
    touch $START_ALIPAY_LOG
    echo "#如果有问题，请携带日志反馈" > $START_ALIPAY_LOG
fi

# Release wake lock to handle screen-off issues
echo lock_me > /sys/power/wake_lock

# Log the script start time
echo "$(date '+%F %T') | Script Start!" >> $START_ALIPAY_LOG

# Get the package name of the foreground app
pkg=`dumpsys window | grep mTopFullscreenOpaqueWindowState | sed 's/ /\n/g' | tail -n 1 | sed 's/\/.*$//g'`
if [ -z "$pkg" ]; then
    echo "$(date '+%F %T') | 当前手机为息屏状态" >> $START_ALIPAY_LOG
else
    echo "$(date '+%F %T') | 前台应用包名为 $pkg" >> $START_ALIPAY_LOG
fi
# Get current time in HHMM format
hh=$(date '+%H%M')

# Read the work list, ignoring commented lines
worklist=$(grep -v '^#' "$WORK_LIST" | cut -f2 -d '=')

# Check application status
current_application(){
    application_status=$(echo "$worklist" | grep -w "${pkg}")
    if [ "$application_status" != "" ]; then
        result="勿扰模式"
    else
        result=""
    fi
}

# Define the function to start and stop Alipay
start_alipay() {
    echo "$(date '+%F %T') | 启动支付宝" >> $START_ALIPAY_LOG
    am start com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 3
    am start --user 999 com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
}

close_alipay() {
    pkg=`dumpsys window | grep mTopFullscreenOpaqueWindowState | sed 's/ /\n/g' | tail -n 1 | sed 's/\/.*$//g'`
    current_application
    if [ -z "$result" ]; then
        am force-stop com.eg.android.AlipayGphone
        sleep 3
        am force-stop --user 999 com.eg.android.AlipayGphone
        echo "$(date '+%F %T') | 关闭支付宝" >> $START_ALIPAY_LOG
    else
        echo "$(date '+%F %T') | 勿扰状态未关闭支付宝" >> $START_ALIPAY_LOG
    fi
}

current_application
# Determine if Alipay should be started based on the time and worklist
if [ $hh -ge 0 ] && [ $hh -le 650 ] && [ -z "$result" ]; then
    start_alipay
    sleep 300
    close_alipay
elif [ $hh -ge 650 ] && [ $hh -le 730 ] && [ -z "$result" ]; then
    start_alipay
elif [ $hh -ge 730 ] && [ $hh -le 2359 ] && [ -z "$result" ]; then
    start_alipay
    sleep 300
    close_alipay
else
    echo "$(date '+%F %T') | 什么也不做" >> $START_ALIPAY_LOG
fi