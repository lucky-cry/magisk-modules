# freeze_logd_switch — logd 冻结切换

Magisk 模块，通过 cgroup v2 freezer 冻结 Android 系统的 `logd` 进程，
在检测到 Scene 守护进程卡死时自动解冻 → 重启 Scene → 延迟后重新冻结。

## 功能

- **冻结 logd**: 通过 cgroup v2 freezer 内核级冻结 logd，不 kill 进程
- **Scene 守护进程监控**: 每分钟检测 Scene 状态，异常时自动恢复
- **渐进式冻结延迟**: 卡死次数越多，冻结前等待越长（1~5分钟）
- **多进程检测**: 检测 scene-daemon 僵尸进程堆积，自动清理
- **互斥锁**: 防止多个恢复流程并发执行
- **手动切换**: Magisk 按钮一键冻结/解冻

## 目录结构

```
freeze_logd_switch/
├── .github/workflows/
│   ├── build-module.yml       # CI 自动打包发版
│   └── sync-to-gitee.yml      # 同步到 Gitee
├── Source/                     # 模块源代码
│   ├── module.prop
│   ├── lib_core.sh             # 核心函数库
│   ├── service.sh              # 开机启动
│   ├── cron_check.sh           # crond 定时检查
│   ├── action.sh               # 手动切换
│   ├── uninstall.sh            # 卸载清理
│   ├── customize.sh            # 安装脚本
│   └── scene_restart.sh        # Scene 重启脚本
├── changelog                   # 更新日志
├── update.json                 # OTA 更新
├── version                     # 版本信息
└── README.md
```

## 更新日志

详见 [changelog](changelog)

## 作者

懒猫
