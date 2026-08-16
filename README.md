# freeze_logd_switch — logd 冻结切换

Magisk 模块，通过 cgroup v2 freezer 冻结 Android 系统的 `logd` 进程，
在检测到 Scene 守护进程卡死时自动解冻 → 重启 Scene → 延迟后重新冻结。

## 功能

- **冻结 logd**: 通过 cgroup v2 freezer 内核级冻结 logd，不 kill 进程
- **循环监控**: 每分钟检查一次；logd 重启导致冻结漂移时自动重新冻结
- **Scene 守护进程监控**: scene-daemon 进程数超过 3 判定异常，自动执行恢复流程
- **渐进式冻结延迟**: 卡死次数越多，冻结前等待越长（1~5 分钟）
- **恢复互斥**: 恢复流程运行期间，定时检查与手动按钮均自动跳过，避免并发竞争
- **多进程检测**: 检测 scene-daemon 僵尸进程堆积，自动清理
- **自适应日志**: 连续 5 次检测正常后暂停每分钟详细日志，出现异常自动恢复
- **手动切换**: Magisk 按钮一键冻结/解冻

## 使用说明

- **手动切换**: Magisk 模块页点击按钮在冻结/解冻间切换；恢复流程进行中按钮会被拒绝（提示稍后再试）。
- **自动重冻（设计如此）**: 手动解冻是临时操作，最迟 1 分钟内下一轮监控会重新冻结 logd。
  如需长期解冻，请直接禁用模块。
- **日志位置**: `/storage/emulated/0/Android/Freeze_logd/log.md`；超过 512KB 自动轮转，
  旧日志保留为同目录 `log.md.old`。
- **静默模式**: 连续 5 次检测正常后暂停每分钟日志；出现异常立即恢复详细日志。
- **调试**: 将 `Source/lib_core.sh` 中 `LOG_LEVEL` 改为 `debug` 并重启服务，
  可输出进程/cgroup 环境等详细日志。

## 目录结构

```
freeze_logd_switch/
├── .github/workflows/
│   ├── build-module.yml       # CI 自动打包发版
│   └── sync-to-gitee.yml      # 同步到 Gitee
├── Source/                     # 模块源代码
│   ├── module.prop
│   ├── lib_core.sh             # 核心函数库（常量/日志/检测/cgroup/恢复，单点维护）
│   ├── service.sh              # 开机启动
│   ├── cron_check.sh           # crond 定时检查
│   ├── action.sh               # 手动切换
│   ├── uninstall.sh            # 卸载清理
│   ├── customize.sh            # 安装脚本
│   └── scene_restart.sh        # Scene 重启脚本
├── update_meta.sh              # 元数据生成脚本（update.json/version/changelog 单一来源）
├── changelog                   # 更新日志
├── update.json                 # OTA 更新
├── version                     # 版本信息
└── README.md
```

## 开发约定

- 修改代码后须递增 `Source/module.prop` 的 version/versionCode，并在 changelog 顶部新增条目。
- 元数据文件（update.json / version）由 `update_meta.sh` 统一生成，勿手工编辑。

## 更新日志

详见 [changelog](changelog)

## 作者

懒猫
