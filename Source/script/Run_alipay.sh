MODDIR=${0%/*}
start_alipay_log=/sdcard/Android/start_alipay/log.md
work_list=/sdcard/Android/start_alipay/勿扰名单.prop
#创建日志文件
if [ ! -f $start_alipay_log ]; then
	mkdir /sdcard/Android/start_alipay
	touch $start_alipay_log
	echo "#如果有问题，请携带日志反馈" >$start_alipay_log
fi
#关闭唤醒锁，尝试解决息屏不处理的问题
echo lock_me > /sys/power/wake_unlock
#开始启动
echo "$(date '+%F %T') | Script Start!" >> $start_alipay_log
#获取前台应用包名
pkg=`dumpsys window | grep mTopFullscreenOpaqueWindowState | sed 's/ /\n/g' | tail -n 1 | sed 's/\/.*$//g'`
echo "$(date '+%F %T') | 前台应用包名为 $pkg" >> $start_alipay_log

#获取当前时间，格式是时分，例如当前是上午8：50，hh=850
hh=`date '+%H%M'`

worklist=$(cat "$work_list" | grep -v '^#' | cut -f2 -d '=')
#echo "$(date '+%F %T') | 勿扰应用包名为 $worklist" >> $start_alipay_log

#pkgs内的应用在前台时，不会启动支付宝任务(类似于游戏模式)
#pkgs=(
#com.eg.android.AlipayGphone
#com.tencent.tmgp.sgame
#com.tencent.jkchess
#)
#检测屏幕状态
Screen_status="$(dumpsys window policy | grep 'mInputRestricted' | cut -d= -f2)"
if [[ "$Screen_status" != "true" ]]; then
  #判断前台应用是否属于pkgs内的应用
  result=$(echo $worklist | grep "${pkg}")
else
  result=""
fi

#echo "$(date '+%F %T') | result = $result" >> $start_alipay_log
#0--6.50 执行启动支付宝5分钟的任务
if [ $hh -ge 0 -a $hh -le 650 ] && [[ "$result" == "" ]]
then
    echo "$(date '+%F %T') | 启动支付宝5分钟" >> $start_alipay_log
    am start com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 1
    am start --user 999 com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 300
    am force-stop com.eg.android.AlipayGphone
    sleep 1
    am force-stop --user 999 com.eg.android.AlipayGphone
    echo "$(date '+%F %T') | 关闭支付宝" >> $start_alipay_log
    
#6.50--7.30 执行启动支付宝的任务
elif [ $hh -ge 650 -a $hh -le 730 ] && [[ "$result" == "" ]]
then
    echo "$(date '+%F %T') | 启动支付宝不限时" >> $start_alipay_log
    am start com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 1
    am start --user 999 com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    
#7.30--23.59 执行启动支付宝5分钟的任务
elif [ $hh -ge 730 -a $hh -le 2359 ] && [[ "$result" == "" ]]
then
    echo "$(date '+%F %T') | 启动支付宝5分钟" >> $start_alipay_log
    am start com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 1
    am start --user 999 com.eg.android.AlipayGphone/com.alipay.mobile.framework.service.common.SchemeStartActivity
    sleep 300
    am force-stop com.eg.android.AlipayGphone
    sleep 1
    am force-stop --user 999 com.eg.android.AlipayGphone
    echo "$(date '+%F %T') | 关闭支付宝" >> $start_alipay_log
    
#不适合适的时间，不做什么
else
    echo "$(date '+%F %T') | 什么也不做" >> $start_alipay_log
 
fi
